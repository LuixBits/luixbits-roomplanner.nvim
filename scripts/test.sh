#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

find "$ROOT/lua" "$ROOT/plugin" "$ROOT/tests" -name '*.lua' -print0 \
  | xargs -0 -n1 luac -p

if command -v stylua >/dev/null 2>&1; then
  stylua --check "$ROOT/lua" "$ROOT/plugin" "$ROOT/tests"
fi

NVIM_LOG_FILE="${TMPDIR:-/tmp}/roomplan-nvim-test.log" \
nvim --headless -u NONE -i NONE -n \
  --cmd "set rtp^=$ROOT" \
  -c "luafile $ROOT/tests/run.lua" \
  -c "qa!"
