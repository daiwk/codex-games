#!/usr/bin/env python3
"""Reproduce the isolated Xu Chu UAL2 rig/recovery experiment outside this repo.

Requires numpy, scipy and Pillow. Optional Godot4.7.2 executes engine mixer checks.
This never exports or edits a production game, GLB, import setting or controller.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

TOOLS = Path(__file__).resolve().parent
WEB = TOOLS.parent
REPO = WEB.parents[1]
STAGES = TOOLS / "xuchu_ual2_lab"
EXPECTED_TARGET = "89f369ccbfce8b5ecd4735ed5f4a18467d23ca4dfc9ec684f51b9c7c30dad43c"
EXPECTED_SOURCE = "8cee20ab1bc55130092447e810e26df22dd2803eccc54f52137a7d54d7ab88a8"
REFERENCE_OUTPUTS = {
    "xuchu-ual2-full-body-prototype.glb": "0f4bb0370506d6b6755f41d90861675fa3d9e790e782117c8fab47f26aaf10b0",
    "xuchu-ual2-twist-rig-experiment.glb": "1846643344eeeeb56479f8655121c327d331a9ca3840a4bf66f37e0cf1f77bca",
    "xuchu-ual2-twist-rig-compatible.glb": "71a6916fc732509cba8a7591926cc267aaebdea51a8935eaa742473342aaf777",
    "xuchu-ual2-family-recoveries.glb": "d940035cc72829f37b277dfdefef60e5a6c5d90513fa38ab39028e306d4b7e76",
}

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def run_logged(command, output, name, env):
    path = output / (name + ".log")
    with path.open("w") as log:
        result = subprocess.run(command, cwd=TOOLS, env=env, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"{name} failed ({result.returncode}); see {path}")
    print(f"done {name}", flush=True)


def prepare_engine_project(output, manifest):
    project = output / "godot-preview"
    project.mkdir(exist_ok=True)
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Xu UAL2 temporary rig lab"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        'renderer/rendering_method.mobile="gl_compatibility"\n'
    )
    assets = {
        "original.glb": output / "xuchu-ual2-full-body-prototype.glb",
        "unfixed.glb": output / "xuchu-ual2-twist-rig-experiment.glb",
        "compatible.glb": output / "xuchu-ual2-family-recoveries.glb",
        "ual2.glb": WEB / "source-assets/animations/ual2/UAL2_Standard.glb",
        "xuchu_saber.glb": WEB / "godot/assets/weapons/xuchu_saber.glb",
    }
    params = '''[remap]
importer="scene"
importer_version=1
type="PackedScene"
[deps]
source_file="res://{name}"
dest_files=[]
[params]
animation/import=true
animation/fps=120
animation/remove_immutable_tracks=true
_subresources={{"nodes":{{"PATH:AnimationPlayer":{{"optimizer/enabled":false,"compression/enabled":false}}}}}}
'''
    for name, source in assets.items():
        shutil.copyfile(source, project / name)
        (project / (name + ".import")).write_text(params.format(name=name))
    for source, name in [("engine_switch_probe.gd", "switch_probe.gd"), ("capture_twist.gd", "capture_twist.gd"), ("capture_feet.gd", "capture_feet.gd")]:
        shutil.copyfile(STAGES / source, project / name)
    (project / "grip.json").write_text(json.dumps(json.loads(manifest.read_text())["xuchu"]["grip"], indent=2))
    return project


def check_numeric_reports(output):
    """Focused preservation/continuity assertions; skin proxies remain review data."""
    rig = json.loads((output / "twist-rig-verification.json").read_text())
    recovery = json.loads((output / "family-recoveries-verification.json").read_text())
    joins = json.loads((output / "family-join-initial.json").read_text())
    checks = []
    def check(name, passed, value):
        checks.append({"name": name, "pass": bool(passed), "value": value})
    legacy = rig["legacy"]
    check("legacy channels unchanged", legacy["all_original_animation_dictionaries_exact"], legacy["animation_count"])
    check("legacy skin equivalence", legacy["max_actual_skin_vertex_error_m"] <= 0.00001, legacy["max_actual_skin_vertex_error_m"])
    full = rig["regular"]
    check("Full authored body preserved", full["max_original_body_error_m"] <= 0.000001, full["max_original_body_error_m"])
    check("Full palm/knife interpolation", full["max_palm_error_m"] <= 0.002 and full["max_tip_error_m"] <= 0.003, [full["max_palm_error_m"], full["max_tip_error_m"]])
    check("Full wrist engineering cone", full["max_wrist_swing_deg"] <= 40.01 and full["max_wrist_twist_deg"] <= 35.01, [full["max_wrist_swing_deg"], full["max_wrist_twist_deg"]])
    check("Full bone lengths", full["max_bone_error_m"] <= 0.000001, full["max_bone_error_m"])
    for alias, row in recovery["clips"].items():
        check(alias + " body preserved", row["max_body_world_error_m"] <= 0.000001, row["max_body_world_error_m"])
        check(alias + " palm/knife preserved", row["max_palm_error_world_m"] <= 0.0005 and row["max_blade_tip_error_world_m"] <= 0.0005, [row["max_palm_error_world_m"], row["max_blade_tip_error_world_m"]])
        check(alias + " wrist/lengths", row["max_wrist_swing_deg"] <= 40.01 and row["max_wrist_twist_deg"] <= 35.01 and row["max_bone_error_m"] <= 0.000001, [row["max_wrist_swing_deg"], row["max_wrist_twist_deg"], row["max_bone_error_m"]])
    for branch, row in joins["joins"].items():
        error = row["mesh_max_vertex_error_world_m"][0]
        check(branch + " raw body join", row["source_body_raw_max_position_m"] <= 0.000001, row["source_body_raw_max_position_m"])
        check(branch + " corrected mesh/palm join", error <= 0.0005 and max(row["palm_base_tip_errors_m"]) <= 0.00005, [error, max(row["palm_base_tip_errors_m"])])
    report = {"mode": "GEOMETRY ONLY / NOT VISUAL ACCEPTANCE", "all_pass": all(c["pass"] for c in checks), "checks": checks}
    (output / "numeric-checks.json").write_text(json.dumps(report, indent=2))
    if not report["all_pass"]:
        raise RuntimeError("numeric preservation check failed; see numeric-checks.json")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--baseline-glb", type=Path, default=WEB / "godot/assets/characters/xuchu.glb")
    parser.add_argument("--manifest", type=Path, default=WEB / "godot/assets/characters/animation_manifest.json")
    parser.add_argument("--godot", type=Path, help="Optional engine binary; imports and runs headless switch probe only.")
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--overwrite", action="store_true", help="Only reuse an existing lab directory carrying this tool's marker.")
    parser.add_argument("--assert-reference-shas", action="store_true", help="Exact same-environment reproduction check, beyond numeric geometry checks.")
    args = parser.parse_args()
    output = args.output_dir.expanduser().resolve()
    if output == Path("/") or output.is_relative_to(REPO):
        parser.error("--output-dir must be outside the repository; production assets are read-only")
    target = args.baseline_glb.expanduser().resolve()
    source = WEB / "source-assets/animations/ual2/UAL2_Standard.glb"
    manifest = args.manifest.expanduser().resolve()
    if any(p.is_relative_to(output) for p in [target, source, manifest]):
        parser.error("the output directory cannot contain an input")
    if sha(target) != EXPECTED_TARGET or sha(source) != EXPECTED_SOURCE:
        parser.error("source/baseline SHA differs from this experiment's frozen inputs")
    if json.loads(manifest.read_text())["xuchu"]["runtime_sha256"] != EXPECTED_TARGET:
        parser.error("manifest Xu runtime SHA does not match the frozen baseline")
    if output.exists() and any(p.is_symlink() for p in output.rglob("*")):
        parser.error("lab outputs cannot contain symlinks; formal assets must remain unreachable for writing")
    marker = output / ".wenfeng-ual2-lab.json"
    if output.exists() and any(output.iterdir()):
        if not marker.exists() or not (args.overwrite or args.verify_only):
            parser.error("output is not empty; reuse requires a valid lab marker and --overwrite or --verify-only")
        previous = json.loads(marker.read_text())
        if previous.get("baseline_sha256") != EXPECTED_TARGET or previous.get("source_sha256") != EXPECTED_SOURCE:
            parser.error("existing lab marker belongs to different inputs")
    elif args.verify_only:
        parser.error("--verify-only requires a previously built lab directory")
    output.mkdir(parents=True, exist_ok=True)
    context = {
        "output_dir": str(output), "source_glb": str(source), "baseline_glb": str(target),
        "manifest": str(manifest), "baseline_sha256": EXPECTED_TARGET, "source_sha256": EXPECTED_SOURCE,
        "manifest_sha256": sha(manifest), "status": "TMP LAB ONLY / NOT VISUAL ACCEPTANCE",
    }
    marker.write_text(json.dumps(context, indent=2))
    env = dict(os.environ, WENFENG_UAL2_LAB_CONTEXT=str(marker), PYTHONDONTWRITEBYTECODE="1")
    if not args.verify_only:
        for stage in ["bake_source", "build_twist_rig", "append_identity", "append_recoveries", "export_root_sidecars"]:
            run_logged([sys.executable, str(STAGES / (stage + ".py"))], output, stage, env)
    for stage in ["verify_rig", "verify_recoveries", "verify_joins"]:
        run_logged([sys.executable, str(STAGES / (stage + ".py"))], output, stage, env)
    check_numeric_reports(output)
    provenance = output / "provenance"
    provenance.mkdir(exist_ok=True)
    licensing = WEB / "source-assets/animations/ual2"
    for name in ["License.txt", "License-Standard-2026-10-24.txt", "SOURCE.txt", "metadata-2026-10-24.json"]:
        shutil.copyfile(licensing / name, provenance / name)
    shutil.copyfile(manifest, provenance / "baseline-animation-manifest.json")
    shutil.copyfile(WEB / "source-assets/README.md", provenance / "model-rights-source-assets-README.md")
    project = prepare_engine_project(output, manifest)
    if args.godot:
        engine = str(args.godot.expanduser().resolve())
        # --import waits for resource imports and then exits; --quit instead
        # requests first-iteration shutdown. Do not combine those lifecycles.
        run_logged([engine, "--headless", "--path", str(project), "--import", "--log-file", str(output / "godot-import-engine.log")], output, "godot-import", env)
        run_logged([engine, "--headless", "--path", str(project), "--script", "res://switch_probe.gd", "--log-file", str(output / "godot-switch-engine.log")], output, "godot-switch", env)
    artifacts = {name: {"sha256": sha(output / name), "reference_sha256": reference, "matches_reference": sha(output / name) == reference} for name, reference in REFERENCE_OUTPUTS.items()}
    if args.assert_reference_shas and not all(a["matches_reference"] for a in artifacts.values()):
        raise RuntimeError("reference artifact SHA mismatch; see output manifest and numeric reports")
    context.update({"artifacts": artifacts, "engine_project": str(project), "source_license": "Quaternius UAL2 Standard CC0 (snapshot in provenance). User character/weapon model rights are separate and are not declared CC0.", "geometry_reports": ["twist-rig-verification.json", "family-recoveries-verification.json", "family-join-initial.json", "numeric-checks.json"], "provenance_file_shas": {p.name: sha(p) for p in sorted(provenance.iterdir()) if p.is_file()}, "native_visual_review": "Not automated or accepted by this command. Use capture_twist.gd in the generated project and review actual images."})
    (output / "lab-manifest.json").write_text(json.dumps(context, indent=2))
    print(json.dumps({"output": str(output), "all_reference_shas_match": all(a["matches_reference"] for a in artifacts.values()), "native_capture_project": str(project)}, indent=2))


if __name__ == "__main__":
    main()
