#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

command -v luac >/dev/null 2>&1 || {
  echo "test: luac is required" >&2
  exit 1
}
command -v nvim >/dev/null 2>&1 || {
  echo "test: nvim is required" >&2
  exit 1
}

find "$ROOT/lua" "$ROOT/plugin" "$ROOT/tests" "$ROOT/scripts" -name '*.lua' -print0 \
  | xargs -0 -n1 luac -p

if command -v stylua >/dev/null 2>&1; then
  stylua --check "$ROOT/lua" "$ROOT/plugin" "$ROOT/tests" "$ROOT/scripts"
fi

NVIM_LOG_FILE="${TMPDIR:-/tmp}/roomplan-nvim-test.log" \
nvim --headless -u NONE -i NONE -n \
  --cmd "set rtp^=$ROOT" \
  -c "luafile $ROOT/tests/run.lua" \
  -c "qa!"
