#!/usr/bin/env python3
"""Build the independent Changban RPG website from the shared Godot assets.

Only this site's dist is replaced. The shared project's main scene and export
preset are changed for the export, then restored byte for byte even on failure.
No model copies or network downloads are required by this build.
"""
import argparse
from contextlib import contextmanager
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT.parent / "wenfeng-web"
GAME = SHARED / "godot"
DIST = ROOT / "dist"
MAX_STATIC_BYTES = 25 * 1024 * 1024
CHUNK_BYTES = 16 * 1024 * 1024
TITLE = "长坂行 · 赵云传"


def run(args):
    subprocess.run([str(value) for value in args], cwd=ROOT, check=True)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def find_godot(requested):
    candidates = [requested] if requested else ["godot", "godot4", "/Applications/Godot.app/Contents/MacOS/Godot"]
    for value in candidates:
        executable = shutil.which(value)
        if executable:
            return Path(executable).resolve()
        path = Path(value).expanduser()
        if path.is_file():
            return path.resolve()
    raise SystemExit("Godot 4.7.2 not found. Use --godot /path/to/Godot or CHANGBAN_GODOT.")


def assignment(text, key, value, section):
    """Set an existing single-line Godot setting, or insert it in its section."""
    replacement = key + "=" + value
    result, count = re.subn(r"^" + re.escape(key) + r"=.*$", lambda _match: replacement, text, flags=re.MULTILINE)
    if count > 1:
        raise ValueError("Ambiguous shared setting: " + key)
    if count:
        return result
    marker = "[" + section + "]"
    if marker not in text:
        raise ValueError("Missing shared configuration section: " + section)
    return text.replace(marker, marker + "\n" + replacement, 1)


@contextmanager
def temporary_rpg_settings(game, template, shell, export_path):
    project = game / "project.godot"
    preset = game / "export_presets.cfg"
    saved_project, saved_preset = project.read_bytes(), preset.read_bytes()
    project_text = saved_project.decode("utf-8")
    preset_text = saved_preset.decode("utf-8")
    project_text = assignment(project_text, "config/name", json.dumps(TITLE, ensure_ascii=False), "application")
    project_text = assignment(project_text, "run/main_scene", '"res://rpg.tscn"', "application")
    project_text = assignment(project_text, "config/description", json.dumps("赵云的骑马探索外传：行旅、试锋、升级与装备。", ensure_ascii=False), "application")
    match = re.search(r"^export_files=PackedStringArray\((.*)\)$", preset_text, re.MULTILINE)
    if not match:
        raise ValueError("Shared Web preset is missing its explicit resource list")
    resources = re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', match.group(1))
    resources += ["res://rpg.tscn"]
    resources += ["res://" + path.relative_to(game).as_posix() for path in sorted((game / "scripts").glob("rpg_*.gd"))]
    resources.append("res://assets/characters/bandit.glb")
    resources = list(dict.fromkeys(resources))
    encoded = "PackedStringArray(" + ", ".join(json.dumps(value, ensure_ascii=False) for value in resources) + ")"
    preset_text = assignment(preset_text, "export_files", encoded, "preset.0")
    preset_text = assignment(preset_text, "export_path", json.dumps(export_path.resolve().as_posix()), "preset.0")
    preset_text = assignment(preset_text, "custom_template/release", json.dumps(template.resolve().as_posix()), "preset.0.options")
    preset_text = assignment(preset_text, "html/custom_html_shell", json.dumps(shell.resolve().as_posix()), "preset.0.options")
    try:
        project.write_bytes(project_text.encode("utf-8"))
        preset.write_bytes(preset_text.encode("utf-8"))
        yield
    finally:
        # Restoration uses the original bytes, not a parsed/reformatted config.
        try:
            project.write_bytes(saved_project)
        finally:
            preset.write_bytes(saved_preset)


def package_assets(stage):
    manifest = {"game": "changban-rpg", "engine": "Godot 4.7.2", "entry_scene": "res://rpg.tscn", "threaded": False, "assets": {}}
    for name, mime in [("index.wasm", "application/wasm"), ("index.pck", "application/octet-stream")]:
        path = stage / name
        raw = path.read_bytes()
        packed = gzip.compress(raw, compresslevel=9, mtime=0)
        if gzip.decompress(packed) != raw:
            raise RuntimeError("Compression verification failed: " + name)
        asset = {"type": mime, "decoded_bytes": len(raw), "download_bytes": len(packed), "sha256": hashlib.sha256(raw).hexdigest()}
        if len(packed) >= MAX_STATIC_BYTES:
            asset["chunks"] = []
            for index, offset in enumerate(range(0, len(packed), CHUNK_BYTES)):
                chunk = packed[offset:offset + CHUNK_BYTES]
                destination = stage / (name + f".gz.part{index:02d}")
                destination.write_bytes(chunk)
                asset["chunks"].append({"file": destination.name, "bytes": len(chunk), "sha256": hashlib.sha256(chunk).hexdigest()})
        else:
            destination = stage / (name + ".gz")
            destination.write_bytes(packed)
            asset["file"] = destination.name
        manifest["assets"][name] = asset
        path.unlink()
        print(f"{name}: {len(raw)/1e6:.2f} MB decoded, {len(packed)/1e6:.2f} MB download", flush=True)
    (stage / "assets-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def copy_credits(stage, godot):
    licenses = stage / "licenses"
    licenses.mkdir(exist_ok=True)
    shutil.copy2(GAME / "THIRD_PARTY_LICENSES.md", licenses / "Game-THIRD-PARTY.txt")
    rpg_provenance = ROOT / "source-assets/THIRD_PARTY_LICENSES.md"
    if rpg_provenance.is_file():
        shutil.copy2(rpg_provenance, licenses / "RPG-THIRD-PARTY.txt")
    for family in ["Sans", "Serif"]:
        shutil.copy2(GAME / f"assets/fonts/Noto{family}-LICENSE.txt", licenses / f"Noto{family}-LICENSE.txt")
    for path in (GAME / "assets/licenses").glob("*.txt"):
        shutil.copy2(path, licenses / path.name)
    run([godot, "--headless", "--path", GAME, "--script", "res://tools/export_engine_licenses.gd", "--", licenses])
    required = ["Game-THIRD-PARTY.txt", "Godot-LICENSE.txt", "Godot-THIRD-PARTY.txt", "NotoSans-LICENSE.txt", "NotoSerif-LICENSE.txt", "KayKit-CC0.txt", "Horse-CC0.txt", "Quaternius-UAL1-CC0.txt", "Quaternius-UAL2-CC0.txt"]
    for name in required:
        if not (licenses / name).is_file():
            raise RuntimeError("Missing distribution license: " + name)
    text = """长坂行 · 赵云传 / Changban Journey

以三国人物为背景的架空骑马探索外传。
原创游戏代码、程序地图、封面插画、程序特效与合成音效。
共享素材来自同仓库的问锋项目；网站运行文件独立打包。

角色（含山贼）、兵器、棕白马外观及马鞍来自用户提供的模型。
这些用户素材不被声明为 CC0。

武将动作：KayKit Character Animations Free 1.1, Kay Lousberg, CC0 1.0.
https://kaylousberg.itch.io/kaykit-character-animations
See licenses/KayKit-CC0.txt

握持手指姿势及归档单手动作：Quaternius Universal Animation Library 1 & 2, CC0 1.0.
https://quaternius.com/
See licenses/Quaternius-UAL1-CC0.txt and Quaternius-UAL2-CC0.txt

马匹骨架与骑行动作：Quaternius Farm Animals Pack, CC0 1.0.
https://quaternius.com/packs/farmanimal.html
See licenses/Horse-CC0.txt

Godot Engine — MIT License
See licenses/Godot-LICENSE.txt and Godot-THIRD-PARTY.txt

Chinese fonts: Noto Sans SC / Noto Serif SC, SIL Open Font License 1.1.
See licenses/NotoSans-LICENSE.txt and NotoSerif-LICENSE.txt

Additional asset provenance: licenses/Game-THIRD-PARTY.txt
RPG-only bandit geometry and rig reconstruction: licenses/RPG-THIRD-PARTY.txt
"""
    (stage / "credits.txt").write_text(text, encoding="utf-8")


def publish_local_dist(stage):
    """Replace only this site's generated folder after a complete good build."""
    backup = ROOT / ".cache/previous-dist"
    if backup.exists():
        shutil.rmtree(backup)
    if DIST.exists():
        DIST.rename(backup)
    try:
        stage.rename(DIST)
    except BaseException:
        if backup.exists():
            backup.rename(DIST)
        raise
    if backup.exists():
        shutil.rmtree(backup)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("CHANGBAN_GODOT") or os.environ.get("WENFENG_GODOT"), help="Godot 4.7.2 executable")
    args = parser.parse_args()
    godot = find_godot(args.godot)
    version = subprocess.run([str(godot), "--version"], capture_output=True, text=True, check=True).stdout.strip()
    if not re.search(r"(?m)^4\.7\.2(?:\.|$)", version):
        raise SystemExit("This project requires Godot 4.7.2; found: " + version)
    template = SHARED / ".cache/web_nothreads_release.zip"
    required = [GAME / "project.godot", GAME / "export_presets.cfg", GAME / "rpg.tscn", GAME / "assets/characters/bandit.glb", ROOT / "web/shell.html", template]
    for path in required:
        if not path.is_file():
            raise SystemExit("Required local build input is missing: " + str(path) + ". No dependencies are downloaded by this script.")
    cache = ROOT / ".cache"
    cache.mkdir(exist_ok=True)
    lock = cache / "shared-project-export.lock"
    try:
        lock_fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        raise SystemExit("An RPG export is already running. If interrupted, check shared configs before removing " + str(lock))
    os.write(lock_fd, str(os.getpid()).encode("ascii"))
    os.close(lock_fd)
    stage = Path(tempfile.mkdtemp(prefix="web-export-", dir=cache))
    saved_hashes = {name: sha256(GAME / name) for name in ["project.godot", "export_presets.cfg"]}
    try:
        with temporary_rpg_settings(GAME, template, ROOT / "web/shell.html", stage / "index.html"):
            run([godot, "--headless", "--editor", "--path", GAME, "--import"])
            run([godot, "--headless", "--path", GAME, "--export-release", "Web", stage / "index.html"])
        restored = {name: sha256(GAME / name) for name in saved_hashes}
        if restored != saved_hashes:
            raise RuntimeError("The shared project configuration was not restored exactly")
        for name in ["web.css", "web-app.js", "landscape.svg", "icon.svg"]:
            shutil.copy2(ROOT / "web" / name, stage / name)
        shutil.copy2(GAME / "assets/fonts/WenfengSerif.otf", stage / "WenfengSerif.otf")
        copy_credits(stage, godot)
        manifest = package_assets(stage)
        files = [path for path in stage.rglob("*") if path.is_file()]
        oversized = [str(path.relative_to(stage)) for path in files if path.stat().st_size >= MAX_STATIC_BYTES]
        if oversized:
            raise RuntimeError("Static files must be smaller than 25 MiB: " + ", ".join(oversized))
        html = (stage / "index.html").read_text()
        if "$GODOT_" in html or "window.CHANGBAN_CONFIG" not in html:
            raise RuntimeError("The RPG HTML shell was not expanded by Godot")
        report = {"game": "changban-rpg", "entry_scene": "res://rpg.tscn", "files": len(files), "download_bytes": sum(path.stat().st_size for path in files), "shared_configuration_sha256": restored, "shared_configuration_restored": True, "assets": manifest["assets"]}
        publish_local_dist(stage)
        (ROOT / "qa").mkdir(exist_ok=True)
        (ROOT / "qa/build-report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"{TITLE}: {report['files']} standalone files, {report['download_bytes']/1e6:.2f} MB; shared settings restored.", flush=True)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
        lock.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
