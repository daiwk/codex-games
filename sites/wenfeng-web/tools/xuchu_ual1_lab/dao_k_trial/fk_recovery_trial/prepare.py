"""Reproduce the frozen 50eb FK-recovery asset candidate outside the repository.

Only asset bakes. No engine, capture, runtime write, build or deployment.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys

sys.dont_write_bytecode = True
LAB = Path(__file__).resolve().parent
PARENT = LAB.parent
TOOLS = LAB.parents[2]
WEB = TOOLS.parent
REPO = WEB.parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path,
                        default=WEB / "source-assets/animations/ual1/UAL1_Standard.glb")
    parser.add_argument("--baseline", type=Path,
                        default=WEB / "godot/assets/characters/xuchu.glb")
    parser.add_argument("--manifest", type=Path,
                        default=WEB / "godot/assets/characters/animation_manifest.json")
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    inputs = {name: getattr(args, name).resolve()
              for name in ["source", "baseline", "manifest"]}
    output = args.output_dir.resolve()
    if output.is_relative_to(REPO) or any(p.is_relative_to(output) for p in inputs.values()):
        parser.error("Output must be outside the repository and cannot contain an input")
    if output.exists():
        parser.error("Output already exists; choose a new directory")
    locks = json.loads((LAB / "locks.json").read_text())
    for name, path in inputs.items():
        if not path.is_file() or sha(path) != locks["inputs"][name + "_sha256"]:
            parser.error(f"Frozen input differs: {name}")
    for relative, expected in locks["generation_dependencies"].items():
        if sha((LAB / relative).resolve()) != expected:
            parser.error(f"Frozen generation dependency differs: {relative}")
    try:
        import numpy
        import scipy
        import PIL
    except ImportError as error:
        parser.error(f"NumPy, SciPy and Pillow are required: {error}")
    output.mkdir(parents=True)
    upstream = output / "upstream"
    command = [sys.executable, "-B", str(PARENT / "prepare.py"),
               "--output-dir", str(upstream)]
    for name, path in inputs.items():
        command.extend(["--" + name, str(path)])
    subprocess.run(command, check=True)
    base = upstream / "xuchu-dao-k-upper-twist.glb"
    support = upstream / "upstream/xuchu-ual1-support-art-trial.glb"
    subprocess.run([sys.executable, "-B", str(LAB / "_prepare_keys.py"),
                    "--base-glb", str(base), "--support-glb", str(support),
                    "--output-dir", str(output)], check=True)
    subprocess.run([sys.executable, "-B", str(LAB / "_bake_full.py"),
                    "--base-glb", str(base),
                    "--keys-glb", str(output / "xuchu-dao-fk-keys.glb"),
                    "--output-dir", str(output)], check=True)
    produced = {}
    for name, expected in locks["outputs"].items():
        produced[name] = sha(output / name)
        if produced[name] != expected:
            raise RuntimeError(f"Exact reproduction failed: {name}; keep output for inspection")
    for name, path in inputs.items():
        if sha(path) != locks["inputs"][name + "_sha256"]:
            raise RuntimeError(f"Input unexpectedly changed: {name}")
    report = {
        "status": "ONLY PERMITTED FOR ISOLATED GAMEPLAY REVIEW / ART NOT FINAL / NOT PB0",
        "input_paths": {name: str(path) for name, path in inputs.items()},
        "input_sha256": locks["inputs"],
        "generation_dependencies": locks["generation_dependencies"],
        "output_sha256": produced,
        "dependencies": {"numpy": numpy.__version__, "scipy": scipy.__version__,
                         "Pillow": PIL.__version__},
        "pending_review": "Slight pause .55–.667 and concentrated blade-rise beat .75–.9; weight/inertia and actual combat transitions not finally accepted",
        "scope": "Rebuild parent 9fbc, author three static FK keys, then one continuous local-rotation candidate. No end-effector or blade-frame solve.",
        "automatic_actions": "Offline asset bakes and provenance only; no engine, capture, network, runtime write, build, deployment or commit",
    }
    (output / "reproduction.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Exact FK recovery candidate reproduced: {output}")


if __name__ == "__main__":
    main()
