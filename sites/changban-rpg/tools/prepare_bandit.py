#!/usr/bin/env python3
"""Rebuild the supplied bandit's broken rig; retain its own mesh, UV and PBR.

The user Tripo geometry is not CC0. Only the KayKit animation and Quaternius
finger-pose references are CC0. A valid user-supplied Mixamo reference provides
bone names/axes, fitted to this model; none of its geometry enters the output.
Requires numpy, scipy and Pillow, like the shared polearm preparation tool.
"""
from copy import deepcopy
from pathlib import Path
import hashlib
import json
import sys
import tempfile

import numpy as np
from scipy.sparse import coo_matrix
from scipy.spatial import cKDTree
from scipy.spatial.transform import Rotation as R

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT.parent / "wenfeng-web"
sys.path.insert(0, str(SHARED / "tools"))
from gltf_tools import GLB, compact_buffers, write_glb
import prepare_polearms as polearms

SOURCE = ROOT / "source-assets/characters/山贼.glb"
REFERENCE = SHARED / "source-assets/characters/zhaoyun.glb"
OUTPUT = SHARED / "godot/assets/characters/bandit.glb"
RUNTIME_MANIFEST = OUTPUT.with_name("animation_manifest.json")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def centre(vertices, y, side=0):
    selected = abs(vertices[:, 1] - y) < .025
    if side:
        selected &= vertices[:, 0] * side > .025
    else:
        selected &= abs(vertices[:, 0]) < .115
    points = vertices[selected]
    if len(points) < 6:
        return np.array([0., y, 0.])
    low, high = np.percentile(points, [8, 92], axis=0)
    return (low + high) * .5


def fitted_joints(reference, vertices):
    world, _ = reference.pose()
    result = {i: world[i][0].copy() for i in reference.order}
    hand_delta, foot_delta = {}, {}
    for side, sign in [("Left", 1), ("Right", -1)]:
        for part in ["Arm", "ForeArm", "Hand"]:
            index = reference.names["mixamorig:" + side + part]
            original = world[index][0]
            x = max(abs(float(original[0])), .19)
            selected = (abs(abs(vertices[:, 0]) - x) < .025) & (vertices[:, 0] * sign > 0) & (vertices[:, 1] > .69) & (vertices[:, 1] < .84)
            points = vertices[selected]
            assert len(points) >= 6, "Bandit arm section must be present"
            result[index][1] = np.median(points[:, 1])
            result[index][2] = np.median(points[:, 2])
        hand = reference.names["mixamorig:" + side + "Hand"]
        hand_delta[side] = result[hand] - world[hand][0]
        for part in ["UpLeg", "Leg", "Foot"]:
            index = reference.names["mixamorig:" + side + part]
            point = world[index][0]
            fitted = centre(vertices, float(point[1]), sign)
            result[index][0] = point[0] * 1.10 if part == "UpLeg" else fitted[0]
            result[index][2] = fitted[2]
        foot = reference.names["mixamorig:" + side + "Foot"]
        foot_delta[side] = result[foot] - world[foot][0]
    for i in reference.order:
        name = reference.nodes[i].get("name", "").replace("mixamorig:", "")
        if name in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End"]:
            result[i][0] = 0.0
            result[i][2] = centre(vertices, float(world[i][0][1]))[2]
        for side in ["Left", "Right"]:
            if name.startswith(side + "Hand") and name != side + "Hand":
                result[i] = world[i][0] + hand_delta[side]
            if name.startswith(side + "Toe"):
                result[i] = world[i][0] + foot_delta[side]
            if name == side + "Shoulder":
                result[i][2] = centre(vertices, float(world[i][0][1]))[2]
    return world, result


def transfer_weights(reference, source_vertices, triangles, fitted):
    primitive = reference.j["meshes"][0]["primitives"][0]
    vertices = reference.accessor(primitive["attributes"]["POSITION"])
    indices = reference.accessor(primitive["attributes"]["JOINTS_0"]).astype(int)
    weights = reference.accessor(primitive["attributes"]["WEIGHTS_0"])
    joints = reference.j["skins"][0]["joints"]
    names = [reference.nodes[i]["name"].replace("mixamorig:", "") for i in joints]
    dense = np.zeros((len(vertices), len(joints)))
    for column in range(4):
        np.add.at(dense, (np.arange(len(vertices)), indices[:, column]), weights[:, column])
    world, _ = reference.pose()
    delta = np.stack([fitted[j] - world[j][0] for j in joints])
    warped_reference = vertices + dense @ delta
    dominant = np.array(names)[dense.argmax(1)]
    output = np.zeros((len(source_vertices), len(joints)))
    labels = np.full(len(source_vertices), "body", dtype="U12")
    labels[(source_vertices[:, 1] > .83) & (abs(source_vertices[:, 0]) < .15)] = "head"
    for side, sign in [("Left", 1), ("Right", -1)]:
        labels[(source_vertices[:, 1] < .46) & (source_vertices[:, 0] * sign > .018)] = side + "leg"
        labels[(source_vertices[:, 1] > .65) & (source_vertices[:, 0] * sign > .17)] = side + "arm"
    for label in np.unique(labels):
        rows = np.flatnonzero(labels == label)
        if label.endswith("leg"):
            side = label[:-3]
            valid = np.array([name.startswith((side + "UpLeg", side + "Leg", side + "Foot", side + "Toe")) for name in dominant])
        elif label.endswith("arm"):
            side = label[:-3]
            valid = np.array([name.startswith((side + "Arm", side + "ForeArm", side + "Hand", side + "Shoulder")) for name in dominant])
        elif label == "head":
            valid = np.array([name.startswith(("Head", "Neck")) for name in dominant])
        else:
            valid = np.array([name in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "RightShoulder", "LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg"] for name in dominant])
        pool = np.flatnonzero(valid)
        distance, nearest = cKDTree(warped_reference[pool]).query(source_vertices[rows], k=12)
        proximity = 1. / np.maximum(distance, .003) ** 2
        proximity /= proximity.sum(1, keepdims=True)
        output[rows] = (dense[pool[nearest]] * proximity[:, :, None]).sum(1)
    # Position welding is for weights only. Vertex indices/UV seams remain exact.
    welded, inverse = np.unique(np.round(source_vertices, 6), axis=0, return_inverse=True)
    sums = np.zeros((len(welded), len(joints)))
    np.add.at(sums, inverse, output)
    sums /= np.bincount(inverse)[:, None]
    edges = np.vstack([triangles[:, [0, 1]], triangles[:, [1, 2]], triangles[:, [2, 0]]])
    edge_a, edge_b = inverse[edges[:, 0]], inverse[edges[:, 1]]
    adjacency = coo_matrix((np.ones(len(edge_a) * 2), (np.r_[edge_a, edge_b], np.r_[edge_b, edge_a])), shape=(len(welded), len(welded))).tocsr()
    degree = np.maximum(np.asarray(adjacency.sum(1)).ravel(), 1.)
    for _ in range(3):
        sums = sums * .65 + (adjacency @ sums) / degree[:, None] * .35
    output = sums[inverse]
    # Never leak the opposing limb's weights across a close leg/arm surface.
    for side, sign in [("Left", 1), ("Right", -1)]:
        other = "Right" if side == "Left" else "Left"
        leg = (source_vertices[:, 1] < .33) & (source_vertices[:, 0] * sign > .018)
        arm = (source_vertices[:, 1] > .65) & (source_vertices[:, 0] * sign > .22)
        forbidden = np.array([name.startswith(other) for name in names])
        output[np.ix_(leg | arm, forbidden)] = 0.0
    indices = np.argsort(output, axis=1)[:, -4:][:, ::-1]
    weights = np.take_along_axis(output, indices, axis=1)
    weights /= weights.sum(1, keepdims=True)
    return indices.astype(np.uint16), weights.astype(np.float32), {"regions": {str(label): int((labels == label).sum()) for label in np.unique(labels)}, "weighted_bones": int(len(np.unique(indices[weights > .01]))), "hips_mass_fraction": float(output[:, names.index("Hips")].sum() / output.sum())}


def rebuild_bind(destination):
    raw, reference = GLB(SOURCE), GLB(REFERENCE)
    scene, blob = deepcopy(raw.j), bytearray(raw.bin)
    primitive = scene["meshes"][0]["primitives"][0]
    vertices = raw.accessor(primitive["attributes"]["POSITION"])
    triangles = raw.accessor(primitive["indices"]).reshape(-1, 3)
    world, fitted = fitted_joints(reference, vertices)
    joints, weights, metrics = transfer_weights(reference, vertices, triangles, fitted)
    scene["nodes"] = deepcopy(reference.nodes)
    for index, node in enumerate(scene["nodes"]):
        node.pop("matrix", None)
        node.pop("scale", None)
        if index in reference.parents:
            parent = reference.parents[index]
            node["translation"] = world[parent][1].inv().apply(fitted[index] - fitted[parent]).tolist()
        else:
            node["translation"] = fitted[index].tolist()
    for node in scene["nodes"]:
        if "mesh" in node:
            node["mesh"], node["skin"], node["name"] = 0, 0, "BanditMesh"
    scene["skins"] = deepcopy(reference.j["skins"])
    scene["animations"] = []
    scene["scenes"], scene["scene"] = [{"nodes": [0]}], 0
    def append(values, kind, component=5126):
        values = np.asarray(values, dtype={5126: "<f4", 5123: "<u2"}[component])
        blob.extend(b"\0" * (-len(blob) % 4))
        view = len(scene["bufferViews"])
        scene["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": values.nbytes})
        blob.extend(values.tobytes())
        scene["accessors"].append({"bufferView": view, "componentType": component, "count": len(values), "type": kind})
        return len(scene["accessors"]) - 1
    primitive["attributes"]["JOINTS_0"] = append(joints, "VEC4", 5123)
    primitive["attributes"]["WEIGHTS_0"] = append(weights, "VEC4")
    inverse = []
    for joint in scene["skins"][0]["joints"]:
        matrix = np.eye(4)
        matrix[:3, :3], matrix[:3, 3] = world[joint][1].as_matrix(), fitted[joint]
        inverse.append(np.linalg.inv(matrix).T.reshape(16))
    scene["skins"][0]["inverseBindMatrices"] = append(inverse, "MAT4")
    blob = compact_buffers(scene, blob)
    write_glb(destination, scene, blob)
    bound = GLB(destination)
    rest, _ = bound.pose()
    ibm = bound.accessor(bound.j["skins"][0]["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    errors = []
    for joint, inverse in zip(bound.j["skins"][0]["joints"], ibm):
        matrix = np.eye(4)
        matrix[:3, :3], matrix[:3, 3] = rest[joint][1].as_matrix(), rest[joint][0]
        errors.append(float(abs(matrix @ inverse - np.eye(4)).max()))
    assert max(errors) < 1e-5, "Rebuilt inverse bind matrices must reproduce the original T-pose"
    metrics["maximum_rest_bind_error"] = max(errors)
    return metrics


def main():
    if not SOURCE.is_file():
        raise SystemExit("Archive the user original at " + str(SOURCE))
    original_sha = digest(SOURCE)
    with tempfile.TemporaryDirectory(prefix="changban-bandit-") as directory:
        temporary = Path(directory)
        bound = temporary / "bandit-bind.glb"
        metrics = rebuild_bind(bound)
        sources = {key: polearms.Sampler(polearms.KAY / ("Rig_Medium_" + name + ".glb")) for key, name in [("melee", "CombatMelee"), ("general", "General"), ("basic", "MovementBasic"), ("advanced", "MovementAdvanced")]}
        fingers = polearms.Sampler(SHARED / "source-assets/animations/ual1/UAL1_Standard.glb")
        polearms.ASSETS, polearms.GAME = temporary, temporary / "game"
        (polearms.GAME / "assets/characters").mkdir(parents=True)
        polearms.CHARACTERS["bandit"] = (bound.name, 3.05)
        clips = polearms.clip_set("zhaoyun")
        clips = {name: clip for name, clip in clips.items() if not name.startswith("RPG")}
        polearms.clip_set = lambda _character: clips
        resize_images = polearms.resize_images
        polearms.resize_images = lambda scene, binary, maximum=1024, normal_maximum=None: resize_images(scene, binary, maximum, 512)
        record = polearms.bake("bandit", bound.name, sources, fingers)
        record["source"] = {"site": "changban-rpg", "file": "source-assets/characters/山贼.glb", "sha256": original_sha}
        record["model_scale"] = 1.80
        record["binding_reconstruction"] = {"reason": "Original zero-length rest rig, corrupted inverse binds and 6993/6994 vertices bound to Hips", "reference": "../wenfeng-web/source-assets/characters/zhaoyun.glb", "reference_sha256": digest(REFERENCE), "geometry": "Entirely the user bandit mesh; original positions, indices, UV and material maps retained", "method": "Anatomically fitted Mixamo rest skeleton; limb-separated weight transfer and welded-topology smoothing", **metrics}
        record["provenance"] = "User Tripo geometry/materials: not CC0. KayKit Free 1.1 animation and Quaternius UAL1 finger pose: CC0-1.0."
        generated = polearms.GAME / "assets/characters/bandit.glb"
        record["runtime_sha256"] = digest(generated)
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        pending = OUTPUT.with_suffix(".glb.tmp")
        try:
            pending.write_bytes(generated.read_bytes())
            pending.replace(OUTPUT)
        finally:
            pending.unlink(missing_ok=True)
        manifest = json.loads(RUNTIME_MANIFEST.read_text())
        manifest["bandit"] = record
        RUNTIME_MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    assert digest(SOURCE) == original_sha, "The user original must remain unchanged"
    print(json.dumps(record, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
