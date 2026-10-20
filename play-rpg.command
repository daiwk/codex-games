#!/bin/sh
cd "$(dirname "$0")" || exit 1
exec ./play.command --game rpg "$@"
