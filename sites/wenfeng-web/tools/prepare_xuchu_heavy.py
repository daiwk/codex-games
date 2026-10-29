"""Reproduce the released Xu saber-heavy assets from archived, immutable inputs.

Only offline asset preparation; the destination must be new and outside Git.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
TOOLS = Path(__file__).resolve().parent
WEB = TOOLS.parent
REPO = WEB.parents[1]
LAB = TOOLS / "xuchu_ual1_lab"
FIT = LAB / "high_guard"
BASELINES = WEB / "source-assets/animations/runtime-baselines"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(script, *args):
    subprocess.run([sys.executable, "-B", str(script), *map(str, args)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output.is_relative_to(REPO) or output.exists():
        parser.error("Choose a new output directory outside the repository")
    locks = json.loads((FIT / "locks.json").read_text())
    for relative, expected in locks["generation_dependencies"].items():
        if sha((FIT / relative).resolve()) != expected:
            parser.error(f"Frozen generation dependency differs: {relative}")
    output.mkdir(parents=True)
    run(LAB / "dao_k_trial/fk_recovery_trial/prepare.py",
        "--baseline", BASELINES / "xuchu-before-source-heavy.glb",
        "--manifest", BASELINES / "manifest-before-xuchu-source-heavy.json",
        "--output-dir", output / "fk")
    model = output / "fk/xuchu-dao-k-fk-recovery.glb"
    run(LAB / "build_k_resource.py", "--source-glb", model,
        "--baseline", model, "--variant", "fk_trial",
        "--output-dir", output / "base-library")
    run(FIT / "bake.py", "--source", model,
        "--output", output / "high-guard.glb", "--tools-dir", TOOLS)
    run(FIT / "build_library.py", "--source", output / "high-guard.glb",
        "--baseline-sidecar", output / "base-library/xuchu_ual1_k.json",
        "--output-dir", output / "runtime")
    shutil.copy2(model, output / "runtime/xuchu.glb")
    produced = {}
    for relative, expected in locks["outputs"].items():
        produced[relative] = sha(output / relative)
        if produced[relative] != expected:
            raise RuntimeError(f"Exact reproduction failed: {relative}")
    (output / "reproduction.json").write_text(json.dumps({
        "output_sha256": produced,
        "generation_dependencies": locks["generation_dependencies"],
        "baseline": str(BASELINES),
        "scope": "Offline source bakes only; no Godot, captures, network, runtime installation or deployment",
    }, indent=2) + "\n")
    print(f"Xu heavy assets reproduced: {output / 'runtime'}")


if __name__ == "__main__":
    main()
