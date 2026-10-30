#!/usr/bin/env python3
"""Rebuild Xu's anatomical J/Q/E/U library from the archived CC0 UAL2 source.

Requires NumPy and SciPy. Does not change xuchu.glb, accepted K, or other heroes.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools/xuchu_blade_family"
CLIPS = ["Sword_Regular_Combo", "Sword_Regular_A", "Sword_Regular_A_Rec",
         "Sword_Regular_B", "Sword_Regular_B_Rec", "Sword_Regular_C",
         "Sword_Block", "OverhandThrow"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(script, *args):
    subprocess.run([sys.executable, str(TOOLS / script), *map(str, args)], check=True)


def main():
    target = ROOT / "godot/assets/characters/xuchu.glb"
    source = ROOT / "source-assets/animations/ual2/UAL2_Standard.glb"
    assert digest(target) == "50ebed213d9f4d90e12935474d6b992ae75e9815774037a2b366134b78ff8a55"
    assert digest(source) == "8cee20ab1bc55130092447e810e26df22dd2803eccc54f52137a7d54d7ab88a8"
    with tempfile.TemporaryDirectory(prefix="wenfeng-xu-blade-") as folder:
        folder = Path(folder)
        frames, contact, game = [folder / name for name in ["frames.glb", "contact.glb", "game.glb"]]
        run("bake_anatomy_fk.py", "--target", target, "--source", source,
            "--output", frames, "--tools-dir", TOOLS, "--leg-frame-align",
            "--root-displacement-ratio", "0.45443943577095475",
            "--foot-ref-source", "Sword_Regular_A", "--foot-ref-target", "Idle",
            "--sole-align-target", "Idle", "--clips", *CLIPS)
        assert digest(frames) == "5ee4e8e1d8292b53be6dd8eba7fbc16dbcff040ecbbfe8ee8ae71c582dc35c67"
        run("bake_source_contact_ground.py", "--target", frames, "--source", source,
            "--output", contact, "--tools-dir", TOOLS, "--clips", *CLIPS)
        assert digest(contact) == "16bd81427e06c1a3a3d0159db24279883cff9d7ea9854ca0824a5aaabb0d7d0a"
        metadata = game.with_suffix(".json")
        run("compile_gameclips.py", "--input", contact, "--output", game, "--meta", metadata)
        run("verify_gameclips.py", "--input", contact, "--output", game,
            "--meta", metadata, "--report", folder / "verification.json")
        assert digest(game) == "1209c08c0cd909b0674767f6e56d84e38cd08d8bc581ac1d5a1316efd75b3385"
        destination = ROOT / "godot/assets/motion/xuchu_blade_family.glb"
        shutil.copyfile(game, destination)
        shutil.copyfile(metadata, destination.with_suffix(".json"))
        print(json.dumps({"asset": str(destination), "sha256": digest(destination)}, indent=2))


if __name__ == "__main__":
    main()
