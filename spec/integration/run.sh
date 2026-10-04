#!/usr/bin/env bash
# Run MiniMenu's integration tests inside a headless KOReader emulator build:
#   KOREADER_DIR=<koreader>/koreader-emulator-x86_64-linux-gnu-debug/koreader spec/integration/run.sh [test.lua ...]
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
plugin="$(cd "$here/../.." && pwd)"
: "${KOREADER_DIR:?set KOREADER_DIR to the emulator koreader directory}"
home="${KO_HOME:-$(mktemp -d)}"
export KO_HOME="$home" MINIMENU_DIR="$plugin"
export LUA_PATH="$here/?.lua;;"
noise='^(ffi[.]|lib_)'

run_one() {
    local t
    t="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    echo "== $(basename "$t")"
    cd "$KOREADER_DIR" || return 1
    ./luajit "$t" 2>&1 | grep -v -E "$noise"
}

status=0
tests=("$@")
if [ ${#tests[@]} -eq 0 ]; then tests=("$here"/*_test.lua); fi
for t in "${tests[@]}"; do
    (run_one "$t") || status=1
done
echo "screenshots: $home/shots"
exit $status
