#!/usr/bin/env python3
"""Extract CC0 jump rotations without changing any supplied/runtime GLB.

Only rotations are exported. CharacterBody supplies height, gravity and floor
collision; runtime FK retains the user's limb lengths and weapon animation.
Preparation dependencies: numpy/scipy (same as the existing animation tools).
"""
from pathlib import Path
import hashlib
import json
import numpy as np
from gltf_tools import GLB

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "godot/assets/motion/jump_motion.json"
HUMAN = ROOT / "source-assets/animations/kaykit/Rig_Medium_MovementBasic.glb"
HORSE = ROOT / "source-assets/animations/horse/Horse.glb"


def rotations(source, name, reference, names):
    duration = source.duration(name)
    times = np.linspace(0., duration, round(duration * 30) + 1)
    tracks = {label: [] for label in names}
    for time in times:
        world, _ = source.pose(name, time)
        for label, node in names.items():
            q = (world[node][1] * reference[node][1].inv()).as_quat()
            if tracks[label] and np.dot(q, tracks[label][-1]) < 0.:
                q = -q
            tracks[label].append([round(float(v), 7) for v in q])
    return {"duration": duration, "times": times.tolist(), "rotations": tracks}


def main():
    human, horse = GLB(HUMAN), GLB(HORSE)
    hrest, _ = human.pose("T-Pose")
    qrest, _ = horse.pose()
    names = {"Hips": human.names["hips"]}
    for side, suffix in [("Left", "l"), ("Right", "r")]:
        for part, source_part in [("UpLeg", "upperleg"), ("Leg", "lowerleg"),
                                  ("Foot", "foot"), ("ToeBase", "toes")]:
            names[side + part] = human.names[source_part + "." + suffix]
    target_names = {n.get("name") for n in GLB(ROOT / "godot/assets/mounts/horse_white.glb").nodes}
    horse_names = {name: node for name, node in horse.names.items()
                   if name in target_names
                   and name not in ["HorseRig", "MountSaddle"]}
    data = {
        "license": "CC0-1.0",
        "scope": "Read-only derivative rotations; no mesh, bind, collision or original GLB edits.",
        "sources": [{"path": str(p.relative_to(ROOT)),
                     "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in [HUMAN, HORSE]],
        "human": {name: rotations(human, name, hrest, names)
                  for name in ["Jump_Start", "Jump_Idle", "Jump_Land"]},
        "horse": {"Gallop_Jump": rotations(horse, "Gallop_Jump", qrest, horse_names)},
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, separators=(",", ":")) + "\n")
    print(OUT.relative_to(ROOT), OUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
