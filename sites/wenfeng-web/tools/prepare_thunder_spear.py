#!/usr/bin/env python3
"""Bake the three ground-duel spear Q phrases onto the existing warrior rigs."""
from concurrent.futures import ProcessPoolExecutor
from copy import deepcopy
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np
from scipy.interpolate import PchipInterpolator
from scipy.spatial.transform import Rotation

from gltf_tools import GLB, compact_buffers, write_glb
from prepare_guanyu_crescent import Rig, normalize, shaft_frame, yaw
from prepare_polearms import fit_polearm_hands


ASSETS = Path(__file__).resolve().parents[1] / "godot/assets/characters"
PREFIX = "DuelThunder"
SCALE = 1.98
HZ = 60
SIDES = ("Left", "Right")
FORWARD = np.array([0., 0., 1.])
UP = np.array([0., 1., 0.])

# Seconds, hip yaw, extra chest yaw, pitch, bank, pelvis XYZ offset,
# desired palm centre XYZ offset, shaft heading/elevation. Positions use
# rig space and are relative to that character's existing idle pose.
READY = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 55.2, 22.)
DRAGON_JOIN = (.38, -14, -9, 10, -3, -.035, -.024, -.012, -.085, .015, -.045, 28, 34)
SERPENT_JOIN = (.52, -25, -9, 13, -4, -.035, -.041, -.042, -.113, .033, -.090, 22, 38)

PHRASES = {
    "zhaoyun": {
        "DragonSnap": [
            READY,
            (.037, -9, -10, 5, -3, -.022, -.014, -.037, -.060, .049, -.125, 36, 30),
            (.068, -11, -8, 9, -4, -.027, -.022, -.055, -.090, .017, -.164, 20, 16),
            (.103, -9, -6, 10, -3, -.020, -.025, -.048, -.101, -.007, -.134, 13, 7),
            (.128, 0, -5, 13, -1, -.013, -.032, .023, -.085, .023, .043, 6, 5),
            (.151, 6, -5, 14, 0, -.008, -.034, .073, -.075, .033, .133, 4, 5),
            (.165, 8, -7, 12, 0, -.006, -.026, .075, -.079, .027, .125, 4, 5),
            (.25, 2, -4, 6, -2, -.020, -.012, .035, -.078, .012, .060, 15, 16),
            DRAGON_JOIN,
        ],
        "DragonDrive": [
            (0, *DRAGON_JOIN[1:]),
            (.061, -17, -10, 13, -4, -.045, -.038, -.040, -.099, -.021, -.135, 22, 21),
            (.107, -10, -7, 14, -2, -.027, -.048, -.034, -.104, -.044, -.111, 12, 4),
            (.131, -1, -6, 17, 1, -.017, -.056, .026, -.100, -.054, .049, 7, 0),
            (.159, 12, -8, 21, 3, -.005, -.064, .084, -.092, -.058, .151, 5, -2),
            (.180, 13, -9, 19, 3, -.003, -.060, .086, -.095, -.053, .145, 5, -1),
            (.235, 9, -7, 17, 1, -.010, -.049, .067, -.097, -.033, .075, 12, 7),
            (.33, 1, -2, 8, -1, -.011, -.025, .024, -.050, -.014, .020, 37, 16),
            (.44, *READY[1:]),
        ],
    },
    "machao": {
        "TigerDrive": [
            READY,
            (.076, -11, -9, 5, -4, -.024, -.020, -.030, -.065, .065, -.121, 43, 40),
            (.128, -18, -11, 10, -6, -.035, -.036, -.053, -.105, .048, -.163, 29, 26),
            (.168, -22, -12, 12, -6, -.041, -.044, -.066, -.114, .019, -.178, 17, 12),
            (.229, -15, -8, 15, -4, -.037, -.055, -.045, -.108, .010, -.151, 12, 7),
            (.278, 5, -7, 22, 2, -.016, -.073, .053, -.097, .006, .046, 6, 5),
            (.344, 16, -8, 25, 4, -.004, -.075, .101, -.090, .011, .154, 5, 2),
            (.426, 15, -8, 23, 3, -.006, -.073, .097, -.092, .007, .145, 5, 2),
            (.51, 12, -7, 20, 2, -.010, -.062, .076, -.097, -.013, .100, 9, 5),
            (.65, 5, -4, 14, 0, -.011, -.039, .046, -.092, -.026, .022, 25, 12),
            (.86, -2, -2, 7, -1, -.005, -.013, .017, -.030, .006, -.011, 49, 20),
            (1.05, *READY[1:]),
        ],
    },
    "zhangfei": {
        "SerpentBrace": [
            READY,
            (.088, -11, -4, 7, -2, -.025, -.024, -.024, -.065, .053, -.045, 47, 37),
            (.184, -22, -9, 14, -4, -.039, -.052, -.035, -.107, .061, -.072, 31, 48),
            (.292, -25, -9, 15, -4, -.039, -.048, -.046, -.116, .041, -.085, 22, 41),
            SERPENT_JOIN,
        ],
        "SerpentDrive": [
            (0, *SERPENT_JOIN[1:]),
            (.103, -28, -10, 15, -6, -.043, -.058, -.042, -.115, .056, -.105, 24, 41),
            (.173, -18, -9, 19, -4, -.039, -.068, -.003, -.124, .029, -.040, 18, 22),
            (.228, -8, -5, 21, 0, -.020, -.069, -.028, -.103, -.020, -.115, 11, 5),
            (.255, 1, -5, 23, 0, -.014, -.079, .041, -.098, -.020, .046, 8, 5),
            (.292, 11, -6, 25, 4, -.002, -.079, .087, -.085, -.027, .162, 5, 3),
            (.377, 13, -7, 23, 3, -.004, -.074, .084, -.091, -.019, .154, 5, 3),
            (.459, 9, -6, 20, 2, -.014, -.065, .072, -.093, -.023, .105, 10, 6),
            (.61, 1, -2, 12, -1, -.021, -.040, .036, -.088, -.020, .039, 28, 12),
            (.78, -3, -3, 6, -2, -.018, -.017, .012, -.041, .010, -.017, 47, 23),
            (.90, *READY[1:]),
        ],
    },
}

# Footfall start/end, ankle X/Z displacement, foot yaw, peak lift. Only the
# swinging boot moves. Zhang Fei's wide brace is retained into the drive.
FOOTFALLS = {
    "DragonSnap": [("Left", .027, .121, -.004, .118, 8, .027),
                   ("Right", .149, .263, -.031, .091, -14, .031)],
    "DragonDrive": [("Right", .034, .143, -.018, .139, -4, .039),
                    ("Left", .157, .274, .019, .137, 6, .030),
                    ("Right", .28, .405, .049, .025, 18, .024)],
    "TigerDrive": [("Right", .035, .112, .008, .087, 4, .027),
                   ("Left", .114, .284, .014, .235, 9, .054),
                   ("Right", .290, .478, -.053, .161, -18, .044),
                   ("Left", .52, .716, -.014, .030, -9, .036),
                   ("Right", .728, 1.00, .053, .058, 18, .029)],
    "SerpentBrace": [("Right", .030, .161, -.054, -.087, -15, .030),
                     ("Left", .166, .310, .049, .058, 12, .027)],
    "SerpentDrive": [("Left", .158, .262, .017, .073, 3, .024),
                     ("Right", .495, .655, .054, .087, 15, .032),
                     ("Left", .684, .852, -.066, -.131, -15, .029)],
}
ADVANCE = {
    "DragonSnap": [(0, 0), (.030, 0), (.151, .12), (.38, .12)],
    "DragonDrive": [(0, 0), (.031, 0), (.181, .135), (.44, .135)],
    "TigerDrive": [(0, 0), (.08, 0), (.28, .28), (1.05, .28)],
}
ACTIVE = {"DragonSnap": (.10, .16), "DragonDrive": (.11, .18),
          "TigerDrive": (.23, .45), "SerpentDrive": (.23, .39)}
CORE = {"Hips": .090, "Spine": .097, "Spine1": .101,
        "Spine2": .104, "Neck": .075, "Head": .090}


def ankle_path(rig, name, previous, t, travel):
    anchors = {}
    for side in SIDES:
        foot = rig.legs[side][-1]
        ankle, turn = previous[side]
        ankle = ankle.copy()
        for step_side, lo, hi, x, z, angle, lift in FOOTFALLS[name]:
            if side != step_side:
                continue
            u = np.clip((t - lo) / (hi - lo), 0, 1)
            transfer = u * u * (3. - 2. * u)
            ankle += np.array([x * transfer, lift * np.sin(np.pi * u)**2, z * transfer])
            turn += angle * transfer
        anchors[side] = (ankle - FORWARD * travel, turn, yaw(turn) * rig.world[foot][1])
    return anchors


def shaft_distance(axis, origin, start, end, point):
    displacement = point - origin
    return np.linalg.norm(displacement - axis * np.clip(np.dot(displacement, axis), start, end))


def bake(rig, length, name, rows, previous):
    authored = np.asarray(rows)
    curve = PchipInterpolator(authored[:, 0], authored[:, 1:], axis=0)
    duration = authored[-1, 0]
    times = np.linspace(0, duration, round(duration * HZ) + 1)
    travel_keys = np.asarray(ADVANCE.get(name, [(0, 0), (duration, 0)]))
    travel_curve = PchipInterpolator(travel_keys[:, 0], travel_keys[:, 1])
    start = rig.rest if previous is None else previous[0]
    starting_world = rig.glb.world(start)
    starting_anchors = ({side: (rig.world[rig.legs[side][-1]][0], 0.) for side in SIDES}
                        if previous is None else previous[1])
    neutral_center = sum(rig.palm(rig.world, side) for side in SIDES) * .5
    history = {"_step_seconds": float(times[1]), "_roll_rate": 620., "_enforce_continuity": True,
               "_centre": sum(rig.palm(starting_world, side) for side in SIDES) * .5}
    history["_fore_guides"] = {side: Rotation.from_quat(rig.rest[arm[1]][1]) for side, arm in rig.arms.items()}
    for side, (shoulder, elbow, hand) in rig.arms.items():
        for role, bone in (("upper", shoulder), ("fore", elbow), ("hand", hand)):
            history[side + "_" + role] = Rotation.from_quat(start[bone][1])
            if role != "hand":
                history[side + "_" + role + "_world"] = starting_world[bone][1]
    frames, measurements = [], []
    for t in times:
        pelvis, chest, pitch, bank, hx, hy, hz, cx, cy, cz, heading, elevation = curve(t)
        pose = deepcopy(rig.rest)
        hip_turn = yaw(pelvis)
        pose[rig.hip][0] += np.array([hx, hy, hz])
        pose[rig.hip][1] = (hip_turn * rig.rest_hip_rotation).as_quat()
        torso = yaw(pelvis + chest) * Rotation.from_euler("xz", [pitch, bank], degrees=True) * yaw(-pelvis)
        for bone_name, weight in (("Spine", .28), ("Spine1", .34), ("Spine2", .38), ("Head", -.50)):
            bone = rig.id(bone_name)
            world = rig.glb.world(pose)
            rig.set_world_rotation(pose, bone, Rotation.from_rotvec(torso.as_rotvec() * weight) * world[bone][1])
        anchors = ankle_path(rig, name, starting_anchors, t, float(travel_curve(t)))
        body = rig.glb.world(pose)
        height_correction = 0.
        for side, (ankle, _, _) in anchors.items():
            upper, knee, foot = rig.legs[side]
            displacement = ankle - body[upper][0]
            radius = np.linalg.norm(pose[knee][0]) + np.linalg.norm(pose[foot][0]) - .008
            vertical = np.sqrt(max(0., radius**2 - displacement[0]**2 - displacement[2]**2))
            height_correction = min(height_correction, vertical + displacement[1])
        pose[rig.hip][0][1] += height_correction
        ankle_error = max(rig.solve_leg(pose, side, ankle, rotation, hip_turn)
                          for side, (ankle, _, rotation) in anchors.items())
        frame = shaft_frame(heading, elevation)
        axis = frame.apply(FORWARD)
        body = rig.glb.world(pose)
        obstacles = [(body[rig.id(bone)][0] + (UP * .057 if bone == "Head" else 0.), radius)
                     for bone, radius in CORE.items()]
        history["_shaft_clearance"] = ((length * .35 / SCALE, length * .65 / SCALE), obstacles)
        history["_upper_guides"] = {side: body[arm[0]][1] for side, arm in rig.arms.items()}
        hand_rotations = {side: frame * rig.neutral_shaft.inv() * rig.world[arm[-1]][1]
                          for side, arm in rig.arms.items()}
        center = neutral_center + np.array([cx, cy + height_correction, cz])
        spacing = .084 - .011 * np.clip((38 - abs(heading)) / 38, 0., 1.)
        if t < 1e-8:
            pose = deepcopy(start)
            spacing = np.linalg.norm(rig.palm(starting_world, "Left") - rig.palm(starting_world, "Right")) * .5
        elif not fit_polearm_hands(rig.glb, pose, axis, hand_rotations, rig.palms, history,
                                   _centre=center, _spacing=spacing):
            raise ValueError(f"No continuous two-hand solution for {name} at {t:.3f}: {history.get('_last_debug')}")
        world = rig.glb.world(pose)
        left, right = [rig.palm(world, side) for side in SIDES]
        axis = normalize(left - right)
        blade = right + axis * length * .65 / SCALE
        tail = right - axis * length * .35 / SCALE
        clearance = min(shaft_distance(axis, right, -length * .35 / SCALE, length * .65 / SCALE, point) - radius
                        for point, radius in obstacles)
        wrist = max(np.rad2deg((Rotation.from_quat(pose[hand][1]) * Rotation.from_quat(rig.rest_bones[hand][1]).inv()).magnitude())
                    for _, _, hand in rig.arms.values())
        measurements.append([t, wrist, np.linalg.norm(left - right) - 2. * spacing, ankle_error,
                             clearance, axis[2], blade[0], blade[1], blade[2], tail[1]])
        frames.append(pose)
    return times, frames, np.asarray(measurements), (frames[-1], {s: (p, h) for s, (p, h, _) in anchors.items()})


def append_character(inputs):
    character, grip, folder = inputs
    source = GLB(ASSETS / f"{character}.glb")
    rig = Rig(source, grip)
    scene = deepcopy(source.j)
    scene["animations"] = [a for a in scene["animations"] if not a["name"].startswith(PREFIX)]
    binary = compact_buffers(scene, source.bin)
    clips, previous = {}, None

    def track(values, kind):
        data = np.asarray(values, dtype="<f4")
        binary.extend(b"\0" * (-len(binary) % 4))
        view = len(scene["bufferViews"])
        scene["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": data.nbytes})
        binary.extend(data.tobytes())
        accessor = {"bufferView": view, "componentType": 5126, "count": len(data), "type": kind}
        if kind == "SCALAR":
            accessor.update(min=[float(data[0])], max=[float(data[-1])])
        scene["accessors"].append(accessor)
        return len(scene["accessors"]) - 1

    for name, rows in PHRASES[character].items():
        times, frames, values, previous = bake(rig, float(grip["weapon_length"]), name, rows, previous)
        alias = PREFIX + name
        time_index = track(times, "SCALAR")
        animation = {"name": alias, "samplers": [], "channels": []}

        def channel(node, mode, values, kind):
            animation["channels"].append({"sampler": len(animation["samplers"]), "target": {"node": node, "path": mode}})
            animation["samplers"].append({"input": time_index, "output": track(values, kind), "interpolation": "LINEAR"})

        for node in source.j["skins"][0]["joints"]:
            keys = [frame[node][1] for frame in frames]
            for i in range(1, len(keys)):
                if np.dot(keys[i], keys[i - 1]) < 0:
                    keys[i] = -keys[i]
            channel(node, "rotation", keys, "VEC4")
        channel(rig.hip, "translation", [frame[rig.hip][0] for frame in frames], "VEC3")
        scene["animations"].append(animation)
        check = {"wrist_max_deg": float(values[:, 1].max()),
                 "grip_error_m": float(np.max(np.abs(values[:, 2])) * SCALE),
                 "plant_error_m": float(values[:, 3].max() * SCALE),
                 "torso_clearance_m": float(values[:, 4].min() * SCALE),
                 "weapon_floor_clearance_m": float(values[:, [7, 9]].min() * SCALE)}
        if name in ACTIVE:
            lo, hi = ACTIVE[name]
            active = values[(times >= lo) & (times <= hi)]
            check.update(active_axis_forward=float(active[:, 5].min()),
                         active_tip_lateral_m=float(np.max(np.abs(active[:, 6])) * SCALE),
                         forward_tip_travel_m=float((active[:, 8].max() - values[times < lo, 8].min()) * SCALE))
        print(character, alias, {key: round(value, 4) for key, value in check.items()}, flush=True)
        if (check["wrist_max_deg"] > 45. or check["grip_error_m"] > .003 or check["plant_error_m"] > .008
                or check["weapon_floor_clearance_m"] < -.02 or check["torso_clearance_m"] < -.014
                or check.get("active_axis_forward", 1.) < .91 or check.get("active_tip_lateral_m", 0.) > .42
                or check.get("forward_tip_travel_m", .50) < .35):
            raise ValueError(f"Unusable spear path for {character}/{alias}: {check}")
        clips[alias] = {"seconds": float(times[-1]), "samples": len(times), "validation": check}
    staged = folder / f"{character}.glb"
    write_glb(staged, scene, binary)
    return character, staged, clips


def main():
    manifest_path = ASSETS / "animation_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    with TemporaryDirectory(prefix=".thunder-spear-", dir=ASSETS) as temporary:
        folder = Path(temporary)
        inputs = [(name, manifest[name]["grip"], folder) for name in PHRASES]
        with ProcessPoolExecutor(max_workers=len(inputs)) as workers:
            stages = list(workers.map(append_character, inputs))
        for character, staged, clips in stages:
            record = manifest[character]
            record["duel_thunder_spear"] = {"scope": "ground-duel spear Q", "sample_hz": HZ, "clips": clips}
            record["runtime_sha256"] = hashlib.sha256(staged.read_bytes()).hexdigest()
        staged_manifest = folder / manifest_path.name
        staged_manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        for _, staged, _ in stages:
            staged.replace(ASSETS / staged.name)
        staged_manifest.replace(manifest_path)


if __name__ == "__main__":
    main()
