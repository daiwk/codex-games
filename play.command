#!/bin/sh
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
    echo "Python 3 is required. Install it from https://www.python.org/downloads/"
    printf "Press Enter to close... "
    read -r answer
    exit 1
fi
python3 ./play.py "$@"
result=$?
if [ "$result" -ne 0 ]; then
    printf "Press Enter to close... "
    read -r answer
fi
exit "$result"
