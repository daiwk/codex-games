#!/usr/bin/env bash
set -euo pipefail

APP_NAME=天阙试炼.app
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SCRIPT_DIR/$APP_NAME"
USER_APPS_DIR="${TIANQUE_INSTALL_DIR:-$HOME/Applications}"
TARGET_APP="$USER_APPS_DIR/$APP_NAME"
NO_LAUNCH="${TIANQUE_NO_LAUNCH:-0}"

pause_on_error() {
  local status=$?
  echo
  echo "安装失败（错误码 $status）。请把这个窗口的文字发给游戏提供者。"
  if [[ -t 0 ]]; then
    read -r -p "按回车键关闭窗口……" _
  fi
  exit "$status"
}
trap pause_on_error ERR

echo "《天阙试炼》一键安装"
echo "正在检查安装包完整性……"
if [[ ! -d "$SOURCE_APP" ]]; then
  echo "找不到 $APP_NAME。请直接从 DMG 中运行本脚本，不要单独复制脚本。" >&2
  false
fi
codesign --verify --deep --strict --verbose=2 "$SOURCE_APP"

echo "正在安装到：$TARGET_APP"
mkdir -p "$USER_APPS_DIR"
STAGING_APP="$USER_APPS_DIR/.tianque-installing-$$.app"
cleanup() {
  rm -rf "$STAGING_APP"
}
trap cleanup EXIT
ditto "$SOURCE_APP" "$STAGING_APP"
xattr -dr com.apple.quarantine "$STAGING_APP" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$STAGING_APP"
rm -rf "$TARGET_APP"
mv "$STAGING_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

echo "安装成功。"
if [[ "$NO_LAUNCH" != "1" ]]; then
  echo "正在启动《天阙试炼》……"
  open "$TARGET_APP"
fi
echo "完成，可以关闭此窗口。"
