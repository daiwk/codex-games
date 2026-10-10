#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME=天阙试炼.app
DMG_PATH="$PROJECT_DIR/dist/TianqueArena-macOS.dmg"

if [[ -n "${GODOT_BIN:-}" ]]; then
  :
elif command -v godot >/dev/null 2>&1; then
  GODOT_BIN="$(command -v godot)"
elif command -v godot4 >/dev/null 2>&1; then
  GODOT_BIN="$(command -v godot4)"
elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
elif [[ -x /private/tmp/godot-4.7.2/Godot.app/Contents/MacOS/Godot ]]; then
  GODOT_BIN=/private/tmp/godot-4.7.2/Godot.app/Contents/MacOS/Godot
else
  echo "Godot 4.7.2 was not found. Run play.command once, or install Godot." >&2
  exit 1
fi

BUILD_DIR="$(mktemp -d /private/tmp/tianque-package-build.XXXXXX)"
STAGE_DIR="$(mktemp -d /private/tmp/tianque-dmg-stage.XXXXXX)"
cleanup() {
  rm -rf "$BUILD_DIR" "$STAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$PROJECT_DIR/dist"

"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-release macOS "$BUILD_DIR/$APP_NAME"
codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME"
codesign --verify --deep --strict --verbose=2 "$BUILD_DIR/$APP_NAME"

ditto "$BUILD_DIR/$APP_NAME" "$STAGE_DIR/$APP_NAME"
cp "$PROJECT_DIR/distribution/首次打开说明.txt" "$STAGE_DIR/首次打开说明.txt"
cp "$PROJECT_DIR/distribution/一键安装.command" "$STAGE_DIR/一键安装.command"
chmod +x "$STAGE_DIR/一键安装.command"
ln -s /Applications "$STAGE_DIR/Applications" 2>/dev/null || true

hdiutil create -volname "天阙试炼" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"
echo "TIANQUE_DMG=$DMG_PATH"
