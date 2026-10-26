#!/usr/bin/env python3
"""Export the Godot snapshot and package portable, gzip-compressed Web assets."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import re

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
GAME = ROOT / "godot"
MAX_STATIC_BYTES = 25 * 1024 * 1024
CHUNK_BYTES = 16 * 1024 * 1024


def run(args):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True)


def find_godot(requested):
    candidates = [requested] if requested else ["godot", "godot4", "/Applications/Godot.app/Contents/MacOS/Godot"]
    for value in candidates:
        executable = shutil.which(value)
        if executable:
            return executable
        path = Path(value).expanduser()
        if path.is_file():
            return str(path.resolve())
    raise SystemExit("Godot 4.7.2 was not found. Pass --godot /path/to/Godot or set WENFENG_GODOT. Local play only needs: python3 play.py")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("WENFENG_GODOT"), help="Godot 4.7.2 executable; also accepts WENFENG_GODOT")
    args = parser.parse_args()
    godot = find_godot(args.godot)
    if not GAME.joinpath("project.godot").exists():
        raise SystemExit("The included godot/ source directory is missing.")
    template = ROOT / ".cache/web_nothreads_release.zip"
    if not template.is_file():
        run([sys.executable, ROOT / "tools/fetch_web_resources.py"])
    DIST.mkdir(exist_ok=True)
    preset = GAME / "export_presets.cfg"
    saved_preset = preset.read_text()
    preset.write_text(re.sub(r'^custom_template/release=.*$', 'custom_template/release="' + template.as_posix() + '"', saved_preset, flags=re.MULTILINE))
    try:
        run([godot, "--headless", "--editor", "--path", GAME, "--import"])
        run([godot, "--headless", "--path", GAME, "--export-release", "Web", DIST / "index.html"])
    finally:
        preset.write_text(saved_preset)
    for name in ["web.css", "web-app.js"]:
        shutil.copy2(ROOT / "web" / name, DIST / name)
    html = (DIST / "index.html").read_text()
    for name in ["web.css", "web-app.js", "index.js"]:
        version = hashlib.sha256((DIST / name).read_bytes()).hexdigest()[:16]
        html = html.replace('"' + name + '"', '"' + name + '?v=' + version + '"')
    (DIST / "index.html").write_text(html)
    shutil.copy2(GAME / "assets/app-icon.svg", DIST / "icon.svg")
    shutil.copy2(GAME / "assets/fonts/WenfengSerif.otf", DIST / "WenfengSerif.otf")
    shutil.copy2(ROOT / "web/courtyard.webp", DIST / "courtyard.webp")

    licenses = DIST / "licenses"
    licenses.mkdir(exist_ok=True)
    shutil.copy2(GAME / "THIRD_PARTY_LICENSES.md", licenses / "Game-THIRD-PARTY.txt")
    for family in ["Sans", "Serif"]:
        shutil.copy2(GAME / f"assets/fonts/Noto{family}-LICENSE.txt", licenses / f"Noto{family}-LICENSE.txt")
    for file in (GAME / "assets/licenses").glob("*.txt"):
        shutil.copy2(file, licenses / file.name)
    run([godot, "--headless", "--path", GAME, "--script", "res://tools/export_engine_licenses.gd", "--", licenses])
    text = "问锋 · Duel of Blades / Web edition\n\n原创游戏代码、庭院、程序特效与合成音效。\n角色与刀剑、两把枪、许褚大刀、青龙刀、丈八蛇矛、方天画戟模型来自本项目的用户提供资源。\n握持手指姿势与单手冲步/架刀（冲刀叠加 KayKit 横切）：Quaternius Universal Animation Library 1 & 2，CC0 1.0。\nhttps://quaternius.com/\n六位武将单双手动作：KayKit Character Animations Free 1.1，CC0 1.0。\nhttps://kaylousberg.itch.io/kaykit-character-animations\nSee licenses/KayKit-CC0.txt\n\n棕马、白马外观与贴图来自用户提供的Tripo模型；运行副本修复绑定。\nHorse skeleton and locomotion: Quaternius Farm Animal Pack, CC0 1.0.\nhttps://quaternius.com/packs/farmanimal.html\nSee licenses/Horse-CC0.txt\n\nGodot Engine — MIT License\nSee licenses/Godot-LICENSE.txt and licenses/Godot-THIRD-PARTY.txt\n\nChinese fonts: Noto Sans SC / Noto Serif SC, SIL Open Font License 1.1.\nSubsetted for this game's UI. See licenses/NotoSans-LICENSE.txt and licenses/NotoSerif-LICENSE.txt\n\nAdditional asset attribution: licenses/Game-THIRD-PARTY.txt\n"
    text += "\nParticle textures: Kenney Particle Pack, CC0 1.0.\nhttps://kenney.nl/assets/particle-pack\nSee licenses/Kenney-Particle-Pack-CC0.txt\n"
    text += "\n单挑特殊招式（2026-10-26）：免费既有 KayKit / Quaternius 动作的角色序列重编，配合程序长矛、刀戟阵列、三刃回旋、冲击前沿和扬尘；未新增动捕或提取商业参考游戏素材。\n七曜龙矛：七支实际长矛、三轮齐射；西凉铁骑：六骑、三路两排；青龙刀阵：三刀错峰；蛇矛破军：五矛两翼收束；无双方天阵：六戟预示后包夹；虎啸回刃：三把当前刀剑扇形抛回。每实体实际接触后才结算伤害，足骑采用不同生成高度。\n骑兵轮廓使用用户提供的马匹、马超与兵器运行副本，四姿态奔跑来自已有 Quaternius CC0 Gallop；每骑4,894三角形，共用网格与姿态纹理；旗帜为程序生成，蹄尘使用既有Kenney CC0纹理。用户提供的模型不声明为CC0。\n派生资源来源与SHA256：Godot源码 assets/vfx/duel/SOURCE.json；详细说明：source-assets/vfx/duel/README.md。\n"
    (DIST / "credits.txt").write_text(text)
    manifest = {"engine": "Godot 4.7.2", "threaded": False, "assets": {}}
    for name, mime in [("index.wasm", "application/wasm"), ("index.pck", "application/octet-stream")]:
        path = DIST / name
        data = path.read_bytes()
        packed = gzip.compress(data, compresslevel=9, mtime=0)
        if gzip.decompress(packed) != data:
            raise RuntimeError(f"Compression verification failed: {name}")
        for old in DIST.glob(name + ".gz*"):
            old.unlink()
        asset = {"type": mime, "decoded_bytes": len(data), "download_bytes": len(packed), "sha256": hashlib.sha256(data).hexdigest()}
        if len(packed) > MAX_STATIC_BYTES:
            asset["chunks"] = []
            for index, offset in enumerate(range(0, len(packed), CHUNK_BYTES)):
                chunk = packed[offset:offset + CHUNK_BYTES]
                destination = DIST / (name + f".gz.part{index:02d}")
                destination.write_bytes(chunk)
                asset["chunks"].append({"file": destination.name, "bytes": len(chunk), "sha256": hashlib.sha256(chunk).hexdigest()})
        else:
            destination = DIST / (name + ".gz")
            destination.write_bytes(packed)
            asset["file"] = destination.name
        manifest["assets"][name] = asset
        path.unlink()
        print(f"{name}: {len(data)/1e6:.2f} MB decoded, {len(packed)/1e6:.2f} MB download", flush=True)
    (DIST / "assets-manifest.json").write_text(json.dumps(manifest, indent=2) + '\n')
    files = [p for p in DIST.rglob('*') if p.is_file()]
    oversized = [p.name for p in files if p.stat().st_size > MAX_STATIC_BYTES]
    if oversized:
        raise RuntimeError(f"Static asset exceeds 25 MiB: {oversized}")
    report = {"files": len(files), "download_bytes": sum(p.stat().st_size for p in files), "assets": manifest["assets"]}
    (ROOT / "qa").mkdir(exist_ok=True)
    (ROOT / "qa/build-report.json").write_text(json.dumps(report, indent=2) + '\n')
    print(f"Web build ready: {len(files)} files, {report['download_bytes']/1e6:.2f} MB total", flush=True)


if __name__ == "__main__":
    main()
