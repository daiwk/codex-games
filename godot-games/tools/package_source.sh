#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_NAME=TianqueArena-Source-v1.0
OUTPUT_DIR="$PROJECT_DIR/dist"
OUTPUT_ZIP="$OUTPUT_DIR/$PACKAGE_NAME.zip"
STAGE_PARENT="$(mktemp -d /private/tmp/tianque-source-package.XXXXXX)"
STAGE_DIR="$STAGE_PARENT/$PACKAGE_NAME"

cleanup() {
  rm -rf "$STAGE_PARENT"
}
trap cleanup EXIT

mkdir -p "$STAGE_DIR" "$OUTPUT_DIR"

copy_path() {
  local relative="$1"
  mkdir -p "$STAGE_DIR/$(dirname "$relative")"
  ditto "$PROJECT_DIR/$relative" "$STAGE_DIR/$relative"
}

for file in \
  project.godot main.tscn export_presets.cfg play.command \
  README.md DEVELOPMENT.md THIRD_PARTY_LICENSES.md SOURCE_PACKAGE_CONTENTS.md \
  .gitignore source/.gdignore distribution/首次打开说明.txt distribution/一键安装.command; do
  copy_path "$file"
done

for directory in scripts assets; do
  copy_path "$directory"
done

for file in \
  source/hero/quaternius_warrior.blend \
  source/cast/guard_rogue.blend \
  source/cast/brute_monk.blend \
  source/cast/caster_wizard.blend \
  source/cast/boss_cleric.blend \
  source/third_party/quaternius/rpg-characters/License.txt \
  source/third_party/quaternius/rpg-characters/SOURCE.txt; do
  copy_path "$file"
done
copy_path source/third_party/quaternius/rpg-characters/upstream

for file in \
  tools/build_rpg_cast.py \
  tools/inspect_glb_raw.py \
  tools/inspect_glb_motion.py \
  tools/inspect_warrior_face.py \
  tools/package_macos.sh \
  tools/package_source.sh; do
  copy_path "$file"
done

for file in qa/preview.png qa/hero-closeup.png qa/hero-attack.png qa/boss-cleric.png; do
  copy_path "$file"
done

find "$STAGE_DIR" -name '.DS_Store' -delete
find "$STAGE_DIR" -name '*.blend1' -delete
find "$STAGE_DIR" -name '__pycache__' -type d -prune -exec rm -rf {} +
find "$STAGE_DIR" -name '*.pyc' -delete

chmod +x "$STAGE_DIR/play.command" "$STAGE_DIR/tools/package_macos.sh" "$STAGE_DIR/tools/package_source.sh"

rm -f "$OUTPUT_ZIP"
(cd "$STAGE_PARENT" && zip -X -q -r "$OUTPUT_ZIP" "$PACKAGE_NAME")
echo "TIANQUE_SOURCE_ZIP=$OUTPUT_ZIP"
