"""Reproduce two unaccepted UAL1 assets locally; no engine, network or install.

Inputs are read-only. Output must be a new directory outside the repository.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True

LAB = Path(__file__).resolve().parent
WEB = LAB.parents[1]
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
    source, baseline, manifest = [p.resolve() for p in
                                  [args.source, args.baseline, args.manifest]]
    output = args.output_dir.resolve()
    if output.is_relative_to(REPO) or any(p.is_relative_to(output) for p in
                                        [source, baseline, manifest]):
        parser.error("Output must be outside the repository and must not contain an input")
    if output.exists():
        parser.error("Output already exists; choose a new directory (nothing is overwritten)")
    locks = json.loads((LAB / "locks.json").read_text())
    inputs = {"source": source, "baseline": baseline, "manifest": manifest}
    for name, path in inputs.items():
        if not path.is_file() or sha(path) != locks["inputs"][name + "_sha256"]:
            parser.error(f"Frozen input differs: {name}")
    for name, expected in locks["helpers"].items():
        if sha(WEB / "tools" / name) != expected:
            parser.error(f"Frozen helper differs: {name}")
    provenance = WEB / "source-assets/animations/ual1"
    for name, expected in locks["license_snapshots"].items():
        if sha(provenance / name) != expected:
            parser.error(f"License/source snapshot differs: {name}")
    # prepare_polearms imports Pillow; fail before creating output if absent.
    try:
        import numpy  # noqa: F401
        import scipy  # noqa: F401
        import PIL  # noqa: F401
    except ImportError as error:
        parser.error(f"NumPy, SciPy and Pillow are required: {error}")
    output.mkdir(parents=True)
    subprocess.run([sys.executable, "-B", str(LAB / "_bake_raw.py"),
                    "--source", str(source), "--baseline", str(baseline),
                    "--output-dir", str(output)], check=True)
    subprocess.run([sys.executable, "-B", str(LAB / "_bake_support.py"),
                    "--raw-glb", str(output / "xuchu-ual1-sword-raw.glb"),
                    "--output-dir", str(output)], check=True)
    for name, expected in locks["outputs"].items():
        if sha(output / name) != expected:
            raise RuntimeError(f"Exact reproduction failed: {name}; preserve output for inspection")
    for name, path in inputs.items():
        if sha(path) != locks["inputs"][name + "_sha256"]:
            raise RuntimeError(f"Input unexpectedly changed: {name}")
    snapshots = output / "provenance"
    snapshots.mkdir()
    for name in locks["license_snapshots"]:
        shutil.copyfile(provenance / name, snapshots / name)
    shutil.copyfile(manifest, snapshots / "baseline-animation-manifest.json")
    report = {
        "status": "RAW AND LOCAL ART TRIAL / NEITHER FINALLY ACCEPTED / NOT INSTALLED",
        "source_variant": "UAL1 Standard non-root version; authored pelvis XYZ retained in raw",
        "input_paths": {name: str(path) for name, path in inputs.items()},
        "input_sha256": locks["inputs"], "helper_sha256": locks["helpers"],
        "output_sha256": {name: sha(output / name) for name in locks["outputs"]},
        "dependencies": {"numpy": numpy.__version__, "scipy": scipy.__version__, "Pillow": PIL.__version__},
        "art_change": "Right-palm/knife orientation changes only in .40–1.0s, up to18deg; source elbow/wrist points, body/legs/timing unchanged",
        "blade_warning": "Recorded maximum tip change34.8cm; art does not preserve raw blade path and cannot inherit raw hit results",
        "automatic_actions": "Two asset bakes, metadata and license snapshots only; no Godot, capture, network, runtime write or deployment",
    }
    (output / "reproduction.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Exact raw/art assets prepared: {output}")


if __name__ == "__main__":
    main()
