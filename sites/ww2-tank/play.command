#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/godot" && pwd)"
engine="${WW2_TANK_GODOT:-}"
if [ -z "$engine" ]; then
    for candidate in godot4 godot /Applications/Godot.app/Contents/MacOS/Godot "$HOME/Downloads/Godot.app/Contents/MacOS/Godot"; do
        if command -v "$candidate" >/dev/null 2>&1; then
            engine="$candidate"
            break
        fi
    done
fi

if [ -z "$engine" ]; then
    printf '%s\n' '未找到 Godot 4。安装到「应用程序」，或用 Godot 导入本目录下的 godot/project.godot。' >&2
    exit 1
fi

"$engine" --headless --path "$project_dir" --import --quiet
exec "$engine" --path "$project_dir" "$@"
