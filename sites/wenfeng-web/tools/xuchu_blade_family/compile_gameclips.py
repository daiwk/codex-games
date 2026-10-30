#!/usr/bin/env python3
"""Append gameplay slices to an anatomical Xu GLB, with separate 120 Hz root XZ.

No retargeting, IK, weapon transforms, blending, or time warping occurs here.
The input asset, skin, geometry, binary prefix and existing aliases are kept.
Requires the adjacent repository gltf_tools.py, NumPy and SciPy.
"""
from argparse import ArgumentParser
from copy import deepcopy
from fractions import Fraction
from pathlib import Path
import hashlib
import json

import numpy as np
from scipy.spatial.transform import Rotation, Slerp
from gltf_tools import GLB, write_glb

HZ = 120
PREFIX = "XuAnatomy_"
COMBO = PREFIX + "Sword_Regular_Combo"
HIP_NAME = "mixamorig:Hips"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def seconds_on_grid(value):
    """Recover exact 120 Hz source duration from float32 GLB endpoints."""
    tick = round(float(value) * HZ)
    result = Fraction(tick, HZ)
    if abs(float(result) - float(value)) > 0.000001:
        raise ValueError(f"Duration {value} is not on the native 120 Hz grid")
    return result


class Source:
    def __init__(self, glb, alias):
        self.glb = glb
        self.alias = alias
        self.duration = seconds_on_grid(glb.duration(alias))
        self.tracks = {}
        for channel in glb.anims[alias]["channels"]:
            key = (channel["target"]["node"], channel["target"]["path"])
            if key[1] not in ("rotation", "translation", "scale"):
                raise ValueError(f"Unsupported anatomical channel: {key}")
            sampler = glb.anims[alias]["samplers"][channel["sampler"]]
            if sampler.get("interpolation", "LINEAR") != "LINEAR":
                raise ValueError("This compiler accepts the baked LINEAR FK aliases only")
            t = glb.accessor(sampler["input"])[:, 0].astype(float)
            v = glb.accessor(sampler["output"]).astype(float)
            if key in self.tracks:
                raise ValueError(f"Duplicate target track: {key}")
            self.tracks[key] = (t, v)

    def values(self, key, times):
        times = np.asarray(times, dtype=float)
        if key not in self.tracks:
            node, prop = key
            default = {"translation": [0, 0, 0], "rotation": [0, 0, 0, 1], "scale": [1, 1, 1]}[prop]
            return np.tile(self.glb.nodes[node].get(prop, default), (len(times), 1)).astype(float)
        t, v = self.tracks[key]
        ts = np.clip(times, t[0], t[-1])
        if len(t) == 1:
            return np.tile(v[0], (len(times), 1))
        if key[1] == "rotation":
            result = Slerp(t, Rotation.from_quat(v))(ts).as_quat()
        else:
            result = np.column_stack([np.interp(ts, t, v[:, axis]) for axis in range(v.shape[1])])
        # Native-grid slices reuse the authored float32 values verbatim. SLERP
        # only fills genuinely intermediate times; no independent joint edits.
        nearest = np.clip(np.searchsorted(t, ts), 0, len(t) - 1)
        left = np.maximum(nearest - 1, 0)
        nearest = np.where(np.abs(t[left] - ts) < np.abs(t[nearest] - ts), left, nearest)
        exact = np.abs(t[nearest] - ts) <= 0.000001
        result[exact] = v[nearest[exact]]
        return result


def compile_library(input_path, output_path, meta_path, actor_scale):
    g = GLB(input_path)
    hip = g.names[HIP_NAME]
    hip_key = (hip, "translation")
    aliases = [COMBO] + [PREFIX + name for name in (
        "Sword_Regular_A_Rec", "Sword_Regular_B_Rec", "OverhandThrow", "Sword_Block")]
    missing = [name for name in aliases if name not in g.anims]
    if missing:
        raise ValueError(f"Missing required original aliases: {missing}")
    source = {name: Source(g, name) for name in aliases}
    combo = source[COMBO]
    if combo.duration != 3:
        raise ValueError(f"Unexpected original Combo duration: {combo.duration}")
    anchor = combo.values(hip_key, [0])[0]
    # A segment is (source alias, source start, source end). Boundaries are exact
    # native grid times; J2 includes the Combo's 1/30 s B lead-in/connection.
    seg = lambda name, begin, end: (name, Fraction(begin), Fraction(end))
    definitions = {
        "XuBladeReady": {"static": True, "segments": [seg(COMBO, 0, 0)], "duration": Fraction(1)},
        "XuBladeJ1": {"chain_time": Fraction(13, 30), "segments": [seg(COMBO, 0, Fraction(13, 30)), seg(PREFIX + "Sword_Regular_A_Rec", 0, source[PREFIX + "Sword_Regular_A_Rec"].duration)]},
        "XuBladeJ2": {"chain_time": Fraction(17, 30), "segments": [seg(COMBO, Fraction(13, 30), 1), seg(PREFIX + "Sword_Regular_B_Rec", 0, source[PREFIX + "Sword_Regular_B_Rec"].duration)]},
        "XuBladeJ3": {"segments": [seg(COMBO, 1, 3)]},
        "XuBladeThrow": {"segments": [seg(PREFIX + "OverhandThrow", 0, source[PREFIX + "OverhandThrow"].duration)]},
        "XuBladeGuard": {"segments": [seg(PREFIX + "Sword_Block", 0, source[PREFIX + "Sword_Block"].duration)]},
        "XuBladeThrowWindup": {"segments": [seg(PREFIX + "OverhandThrow", 0, Fraction(11, 30))]},
        "XuBladeThrowFollow": {"segments": [seg(PREFIX + "OverhandThrow", Fraction(11, 30), source[PREFIX + "OverhandThrow"].duration)]},
        "XuBladeGuardEnter": {"segments": [seg(PREFIX + "Sword_Block", 0, Fraction(1, 2))]},
        "XuBladeGuardExit": {"segments": [seg(PREFIX + "Sword_Block", Fraction(1, 2), source[PREFIX + "Sword_Block"].duration)]},
    }
    collisions = sorted(set(definitions) & set(g.anims))
    if collisions:
        raise ValueError(f"Output aliases already exist: {collisions}")
    scene = deepcopy(g.j)
    blob = bytearray(g.bin)

    def append(values, kind):
        values = np.asarray(values, dtype="<f4")
        blob.extend(b"\0" * (-len(blob) % 4))
        vi = len(scene["bufferViews"])
        scene["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": values.nbytes})
        blob.extend(values.tobytes())
        ac = {"bufferView": vi, "componentType": 5126, "count": len(values), "type": kind}
        if kind == "SCALAR":
            ac.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
        scene["accessors"].append(ac)
        return len(scene["accessors"]) - 1

    metadata = {
        "input_sha256": sha(input_path), "compiler_sha256": sha(__file__),
        "schema": "XuBladeGameClips-v1", "sample_hz": HZ, "actor_scale": actor_scale,
        "root_bone": HIP_NAME, "root_anchor_local_model": anchor.tolist(),
        "root_coordinates": "Hips parent/Armature model coordinates (glTF right-handed +Y up); no axis swap. Runtime world delta = actor starting basis * root delta model * character model scale. All curves have Y=0; skeleton retains original source Hips Y.",
        "root_policy": "Every generated Hips XZ equals Combo@0 common anchor. Each clip root_delta_model starts at zero. For appended recovery, add recovery(t)-recovery(0) to preceding segment final delta. Runtime accumulates actual CharacterBody movement at J chain points rather than resetting character origin.",
        "pose_policy": "All source local rotations/scales and translations except Hips XZ are retained at native 120Hz; no blend, IK, per-joint override, weapon modification or timewarp. Original scene/skin/mesh/aliases and BIN prefix retained.",
        "native_combo_chain_times": [float(Fraction(13, 30)), 1.0],
        "native_j2_connector_duration": float(Fraction(1, 30)),
        "original_aliases": list(g.anims), "clips": {},
    }
    audits = {}
    for alias, definition in definitions.items():
        segments = definition["segments"]
        duration = definition.get("duration", sum((end - start for _, start, end in segments), Fraction(0)))
        ticks = int(duration * HZ)
        if duration * HZ != ticks:
            raise ValueError(f"Non-native endpoint: {alias} {duration}")
        times = np.arange(ticks + 1, dtype=float) / HZ
        keys = sorted(set().union(*(set(source[name].tracks) for name, _, _ in segments)))
        values = {key: np.empty((len(times), 4 if key[1] == "rotation" else 3)) for key in keys}
        root = np.zeros((len(times), 3), dtype=float)
        cumulative = np.zeros(3)
        segment_metadata = []
        cursor = Fraction(0)
        previous_end = None
        seam_report = []
        for part, (name, start, end) in enumerate(segments):
            src = source[name]
            if not (0 <= start <= end <= src.duration):
                raise ValueError(f"Invalid source range {name} {start}:{end}")
            span = end - start
            if definition.get("static"):
                indices = np.arange(len(times))
                source_times = np.zeros(len(indices)) + float(start)
            else:
                first = int(cursor * HZ) + (1 if part else 0)
                last = int((cursor + span) * HZ)
                indices = np.arange(first, last + 1)
                source_times = float(start) + times[indices] - float(cursor)
            start_hip = src.values(hip_key, [float(start)])[0]
            end_hip = src.values(hip_key, [float(end)])[0]
            for key in keys:
                values[key][indices] = src.values(key, source_times)
            hips = src.values(hip_key, source_times)
            root[indices] = cumulative + hips - start_hip
            root[indices, 1] = 0
            if previous_end is not None:
                rotation_deltas = []
                for key in keys:
                    if key[1] == "rotation":
                        q1 = previous_end[key]
                        q2 = src.values(key, [float(start)])[0]
                        rotation_deltas.append((float(np.degrees((Rotation.from_quat(q1).inv() * Rotation.from_quat(q2)).magnitude())), g.nodes[key[0]].get("name", str(key[0]))))
                seam_report.append({"time": float(cursor), "max_source_local_rotation_difference_deg": max(rotation_deltas), "source_hips_y_difference_model": float(start_hip[1] - previous_end[hip_key][1])})
            previous_end = {key: src.values(key, [float(end)])[0] for key in keys}
            segment_metadata.append({
                "source_alias": name, "source_start": float(start), "source_end": float(end),
                "output_start": float(cursor), "output_end": float(cursor + span),
                "source_start_offset_from_A0_model": [float(start_hip[0] - anchor[0]), 0.0, float(start_hip[2] - anchor[2])],
                "root_accumulated_start_model": cumulative.tolist(),
                "root_segment_delta_model": [float(end_hip[0] - start_hip[0]), 0.0, float(end_hip[2] - start_hip[2])],
            })
            cumulative += end_hip - start_hip
            cumulative[1] = 0
            cursor += span
        original_hip = values[hip_key].copy()
        values[hip_key][:, 0] = anchor[0]
        values[hip_key][:, 2] = anchor[2]
        animation = {"name": alias, "channels": [], "samplers": []}
        time_accessor = append(times[:, None], "SCALAR")
        for key in keys:
            node, prop = key
            vals = values[key].copy()
            if prop == "rotation":
                # Quaternion sign changes preserve orientation and prevent long
                # interpolation arcs; authored angles and axes are untouched.
                for i in range(1, len(vals)):
                    if np.dot(vals[i - 1], vals[i]) < 0:
                        vals[i] *= -1
            animation["samplers"].append({"input": time_accessor, "output": append(vals, "VEC4" if prop == "rotation" else "VEC3"), "interpolation": "LINEAR"})
            animation["channels"].append({"target": {"node": node, "path": prop}, "sampler": len(animation["samplers"]) - 1})
        scene["animations"].append(animation)
        metadata["clips"][alias] = {
            "duration": float(duration), "duration_fraction": str(duration), "samples": len(times),
            "static": bool(definition.get("static")), "chain_time": float(definition["chain_time"]) if "chain_time" in definition else None,
            "segments": segment_metadata, "source_seams": seam_report,
            "times": times.tolist(), "root_delta_model": root.tolist(), "root_end_model": root[-1].tolist(),
        }
        audits[alias] = {"hips_y_max_change": float(np.max(np.abs(original_hip[:, 1] - values[hip_key][:, 1]))), "fixed_hips_xz_max_error": float(np.max(np.abs(values[hip_key][:, [0, 2]] - anchor[[0, 2]])))}
    assert blob[:len(g.bin)] == g.bin
    for key, value in g.j.items():
        if key not in ("animations", "accessors", "bufferViews", "buffers"):
            assert scene[key] == value, f"Unexpected asset/skin change: {key}"
    assert scene["animations"][:len(g.j["animations"])] == g.j["animations"]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    meta_path.parent.mkdir(parents=True, exist_ok=True)
    write_glb(output_path, scene, blob)
    metadata["output_sha256"] = sha(output_path)
    metadata["verification"] = {"original_asset_and_skin_preserved": True, "original_aliases_preserved": True, "original_binary_prefix_preserved": True, "pose_audit": audits}
    meta_path.write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"output_sha256": metadata["output_sha256"], "input_sha256": metadata["input_sha256"], "clips": {name: {key: value[key] for key in ("duration", "samples", "chain_time", "root_end_model")} for name, value in metadata["clips"].items()}}, indent=2))


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--meta", type=Path, required=True)
    parser.add_argument("--actor-scale", type=float, default=2.15, help="Metadata only; root curves remain in model units")
    args = parser.parse_args()
    if args.input.resolve() in (args.output.resolve(), args.meta.resolve()):
        parser.error("Input must never be overwritten")
    compile_library(args.input, args.output, args.meta, args.actor_scale)


if __name__ == "__main__":
    main()
