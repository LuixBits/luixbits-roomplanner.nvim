#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

NVIM_LOG_FILE="${TMPDIR:-/tmp}/roomplan-nvim-benchmark.log" \
nvim --headless -u NONE -i NONE -n \
  --cmd "set rtp^=$ROOT" \
  -c "luafile $ROOT/scripts/benchmark.lua" \
  -c "qa!"
