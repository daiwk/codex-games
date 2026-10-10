#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
GODOT_BIN=""

if command -v godot >/dev/null 2>&1; then
  GODOT_BIN="$(command -v godot)"
elif command -v godot4 >/dev/null 2>&1; then
  GODOT_BIN="$(command -v godot4)"
elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
elif [[ -x /private/tmp/godot-4.7.2/Godot.app/Contents/MacOS/Godot ]]; then
  GODOT_BIN=/private/tmp/godot-4.7.2/Godot.app/Contents/MacOS/Godot
else
  ARCHIVE=/private/tmp/Godot_v4.7.2-stable_macos.universal.zip
  INSTALL_DIR=/private/tmp/godot-4.7.2
  echo "Godot was not found. Downloading the free official Godot 4.7.2 runtime..."
  curl -L --fail --progress-bar \
    -o "$ARCHIVE" \
    https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_macos.universal.zip
  mkdir -p "$INSTALL_DIR"
  unzip -q -o "$ARCHIVE" -d "$INSTALL_DIR"
  GODOT_BIN="$INSTALL_DIR/Godot.app/Contents/MacOS/Godot"
fi

exec "$GODOT_BIN" --path "$PROJECT_DIR"
