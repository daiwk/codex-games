"""Prepare the frozen, rejected-motion combat experiment outside the repo.

This tool copies explicit local inputs, applies one checked patch and bakes
aliases/root data. It never downloads, imports, renders, deploys or commits.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys

LAB = Path(__file__).resolve().parent
WEB = LAB.parents[1]
REPO = WEB.parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=WEB / "godot",
                        help="Stable Godot project matching locks.json")
    parser.add_argument("--rig-glb", type=Path, required=True,
                        help="Explicit local rig-lab d940 family-recoveries GLB")
    parser.add_argument("--output-dir", type=Path, required=True,
                        help="A new directory outside the repository")
    args = parser.parse_args()
    baseline = args.baseline.resolve()
    rig = args.rig_glb.resolve()
    output = args.output_dir.resolve()
    if output.is_relative_to(REPO) or baseline.is_relative_to(output) or rig.is_relative_to(output):
        parser.error("Output must be outside the repository and must not contain either input")
    if output.exists():
        parser.error("Output already exists; choose a new directory (nothing is overwritten)")
    locks = json.loads((LAB / "locks.json").read_text())
    for name, expected in locks["baseline_files"].items():
        path = baseline / name
        if not path.is_file() or sha(path) != expected:
            parser.error(f"Baseline mismatch: {name}; use the documented stable checkout")
    if not rig.is_file() or sha(rig) != locks["rig_glb_sha256"]:
        parser.error("Rig must be the exact d940 family-recoveries input")
    if sha(WEB / "tools/gltf_tools.py") != locks["gltf_tools_sha256"]:
        parser.error("gltf_tools.py differs from the frozen bake helper")
    patch = shutil.which("patch")
    if patch is None:
        parser.error("The local patch executable is required")
    # Fail on missing numerical dependencies before copying any project files.
    try:
        import numpy  # noqa: F401
        import scipy  # noqa: F401
    except ImportError as error:
        parser.error(f"NumPy and SciPy are required: {error}")

    project = output / "godot"
    output.mkdir(parents=True)
    shutil.copytree(baseline, project,
                    ignore=shutil.ignore_patterns(".godot", ".git", "*.log", "__pycache__"))
    subprocess.run([patch, "--batch", "--forward", "--fuzz=0", "-p1", "-d", str(output)],
                   input=(LAB / "experiment.patch").read_text(), text=True, check=True)
    subprocess.run([sys.executable, str(LAB / "bake_game_aliases.py"),
                    "--rig-glb", str(rig), "--project", str(project),
                    "--metadata", str(output / "motion_manifest.json")], check=True)
    qa = project / "tools/xuchu_source_combo_lab"
    qa.mkdir(parents=True, exist_ok=True)
    for name in ["capture_dynamic.gd", "combat_cases.gd", "native_capture_bridge.gd"]:
        shutil.copyfile(LAB / name, qa / name)
    for name, expected in locks["prepared_files"].items():
        if sha(project / name) != expected:
            raise RuntimeError(f"Prepared script hash differs: {name}")
    if sha(project / "assets/characters/xuchu.glb") != locks["prepared_model_sha256"]:
        raise RuntimeError("Prepared model is not the frozen b531 experiment")
    manifest = {
        "status": "REJECTED MOTION SOURCE / FROZEN MECHANISM EXPERIMENT / NOT SHIPPED",
        "baseline_commit": locks["baseline_commit"],
        "baseline": str(baseline), "rig_input": str(rig), "output": str(output),
        "baseline_hashes": locks["baseline_files"], "rig_sha256": sha(rig),
        "prepared_scripts": {name: sha(project / name) for name in locks["prepared_files"]},
        "prepared_model_sha256": sha(project / "assets/characters/xuchu.glb"),
        "accepted_zhao_sha256": sha(project / "assets/characters/zhaoyun.glb"),
        "patch_sha256": sha(LAB / "experiment.patch"),
        "qa_script_hashes": {name: sha(qa / name) for name in
                             ["capture_dynamic.gd", "combat_cases.gd", "native_capture_bridge.gd"]},
        "automatic_actions": "copy local inputs, apply exact patch, bake aliases/root sidecar only",
        "balance_warning": "Same-outcome shares do not cap mixed block/parry rewards; see README",
    }
    (output / "prepare-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared isolated experiment: {project}")
    print("No Godot import, test, window, network request or deployment was started.")


if __name__ == "__main__":
    main()
