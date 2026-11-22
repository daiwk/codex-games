#!/usr/bin/env python3
"""Export 二战：装甲战线 as a static, single-threaded Godot Web build."""

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE_NAME = "web_nothreads_release.zip"
CHUNK_BYTES = 16 * 1024 * 1024
ENGINE_LICENSE_SCRIPT = """extends SceneTree

func _initialize() -> void:
	var directory := OS.get_cmdline_user_args()[0]
	var license_file := FileAccess.open(directory.path_join("Godot-LICENSE.txt"), FileAccess.WRITE)
	license_file.store_string(Engine.get_license_text() + "\\n")
	var notices_file := FileAccess.open(directory.path_join("Godot-THIRD-PARTY.txt"), FileAccess.WRITE)
	for component in Engine.get_copyright_info():
		notices_file.store_string(str(component) + "\\n\\n")
	var license_texts := Engine.get_license_info()
	for license_name in license_texts:
		notices_file.store_string(str(license_name) + "\\n" + str(license_texts[license_name]) + "\\n\\n")
	quit()
"""


def find_godot(requested):
    candidates = [requested] if requested else [
        "godot4",
        "godot",
        "/Applications/Godot.app/Contents/MacOS/Godot",
        str(Path.home() / "Downloads/Godot.app/Contents/MacOS/Godot"),
    ]
    for candidate in candidates:
        if executable := shutil.which(str(Path(candidate).expanduser())):
            return executable
    raise SystemExit("Godot was not found. Pass --godot or set WW2_TANK_GODOT.")


def find_template(requested, version):
    if requested:
        template = Path(requested).expanduser().resolve()
        if not template.is_file():
            raise SystemExit(f"Missing export template: {template}")
        return template
    candidates = [ROOT / ".cache" / TEMPLATE_NAME]
    if version.startswith("4.7.2."):
        candidates.append(ROOT.parent / "wenfeng-web" / ".cache" / TEMPLATE_NAME)
    return next((path for path in candidates if path.is_file()), None)


def run_godot(godot, workdir, *arguments):
    result = subprocess.run(
        [godot, "--headless", "--quiet", "--path", str(workdir / "godot"),
         "--log-file", str(workdir / "godot.log"), *map(str, arguments)],
        capture_output=True,
        text=True,
    )
    message = result.stdout + result.stderr
    if result.returncode or "SCRIPT ERROR:" in message:
        raise RuntimeError(message.strip() or f"Godot exited with code {result.returncode}")


def export_project(godot, template, workdir):
    game_dir = workdir / "godot"
    shutil.copytree(ROOT / "godot", game_dir, ignore=shutil.ignore_patterns(".godot", ".DS_Store", "qa"))
    if template is not None:
        preset = game_dir / "export_presets.cfg"
        content = preset.read_text(encoding="utf-8")
        setting = f"custom_template/release={json.dumps(str(template), ensure_ascii=False)}"
        preset.write_text(content.replace('custom_template/release=""', setting), encoding="utf-8")
    export_dir = workdir / "export"
    export_dir.mkdir()
    run_godot(godot, workdir, "--editor", "--import")
    run_godot(godot, workdir, "--export-release", "Web", export_dir / "game.html")
    return export_dir


def patch_engine_download_errors(engine):
    # Surface interrupted download/decompression streams in Engine.startGame.
    original = (
        "\t\t\t\tonloadprogress(reader, controller).then(function () {\n"
        "\t\t\t\t\tcontroller.close();\n"
        "\t\t\t\t});"
    )
    patched = original.removesuffix("});") + (
        "}).catch(function (error) {\n"
        "\t\t\t\t\tcontroller.error(error);\n"
        "\t\t\t\t});"
    )
    source = engine.read_text(encoding="utf-8")
    if original in source:
        engine.write_text(source.replace(original, patched, 1), encoding="utf-8")


def version_shell_assets(package):
    shell = package / "index.html"
    html = shell.read_text(encoding="utf-8")
    for name in ("game.js", "web-app.js", "web.css"):
        digest = hashlib.sha256((package / name).read_bytes()).hexdigest()[:16]
        html = html.replace(f'"{name}"', f'"{name}?v={digest}"')
    shell.write_text(html, encoding="utf-8")


def pack_asset(source, package, mime_type):
    data = source.read_bytes()
    compressed = gzip.compress(data, compresslevel=9, mtime=0)
    if gzip.decompress(compressed) != data:
        raise RuntimeError(f"Compression verification failed: {source.name}")
    asset = {
        "type": mime_type,
        "decoded_bytes": len(data),
        "download_bytes": len(compressed),
        "sha256": hashlib.sha256(data).hexdigest(),
    }
    output_name = source.name + ".gz"
    if len(compressed) <= CHUNK_BYTES:
        (package / output_name).write_bytes(compressed)
        asset["file"] = output_name
    else:
        chunks = []
        for offset in range(0, len(compressed), CHUNK_BYTES):
            name = f"{output_name}.part{len(chunks):02d}"
            fragment = compressed[offset:offset + CHUNK_BYTES]
            (package / name).write_bytes(fragment)
            chunks.append({"file": name, "bytes": len(fragment)})
        asset["chunks"] = chunks
    print(f"{source.name}: {len(data) / 1e6:.2f} MB decoded, {len(compressed) / 1e6:.2f} MB download")
    return asset


def write_licenses(godot, workdir, package):
    licenses = package / "licenses"
    licenses.mkdir(exist_ok=True)
    script = workdir / "engine_license.gd"
    script.write_text(ENGINE_LICENSE_SCRIPT, encoding="utf-8")
    run_godot(godot, workdir, "--script", script, "--", licenses)
    for path in sorted((ROOT / "godot" / "assets").rglob("*LICENSE*.txt")):
        shutil.copy2(path, licenses / path.name)
    font_credit = ""
    if (licenses / "NotoSans-LICENSE.txt").is_file():
        font_credit = "\nNoto Sans CJK SC — SIL Open Font License 1.1\nlicenses/NotoSans-LICENSE.txt\n"
    rifle_credit = "\nLee Enfield — Lucian Pavel, CC0 1.0\nlicenses/LeeEnfield-LICENSE.txt\n"
    (package / "credits.txt").write_text(
        "二战：装甲战线\n\n坦克、石墙、炮弹、步兵和飞机模型由用户提供。\n"
        "Godot Engine — MIT License\n"
        "licenses/Godot-LICENSE.txt\nlicenses/Godot-THIRD-PARTY.txt\n"
        + font_credit + rifle_credit,
        encoding="utf-8",
    )


def build(godot, template, version, output):
    web = ROOT / "web"
    if not (web / "index.html").is_file():
        raise SystemExit("The web/index.html shell is missing.")
    with tempfile.TemporaryDirectory(prefix="stonewall-web-") as temporary:
        workdir = Path(temporary)
        export_dir = export_project(godot, template, workdir)
        package = workdir / "dist"
        shutil.copytree(web, package, ignore=shutil.ignore_patterns(".DS_Store"))
        for script in export_dir.glob("game*.js"):
            shutil.copy2(script, package / script.name)
        patch_engine_download_errors(package / "game.js")
        version_shell_assets(package)
        manifest = {
            "engine": "Godot " + ".".join(version.split(".")[:3]),
            "threaded": False,
            "assets": {
                "game.wasm": pack_asset(export_dir / "game.wasm", package, "application/wasm"),
                "game.pck": pack_asset(export_dir / "game.pck", package, "application/octet-stream"),
            },
        }
        (package / "assets-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        write_licenses(godot, workdir, package)
        shutil.copytree(package, output, dirs_exist_ok=True)
        for pattern in ("game.wasm.gz*", "game.pck.gz*"):
            for stale in output.glob(pattern):
                if stale.is_file() and not (package / stale.name).exists():
                    stale.unlink()
        size = sum(path.stat().st_size for path in package.rglob("*") if path.is_file())
        print(f"Web build ready: {output} ({size / 1e6:.2f} MB)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("WW2_TANK_GODOT"))
    parser.add_argument("--template", help="Path to the official single-threaded Web release template")
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    godot = find_godot(args.godot)
    version = subprocess.check_output([godot, "--version"], text=True).strip()
    template = find_template(args.template, version)
    try:
        build(godot, template, version, args.output.expanduser().resolve())
    except (OSError, RuntimeError) as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()
