#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
export NVIM_LOG_FILE="${TMPDIR:-/tmp}/roomplan-nvim-release.log"

command -v jq >/dev/null 2>&1 || {
  echo "release-check: jq is required" >&2
  exit 1
}
command -v nix >/dev/null 2>&1 || {
  echo "release-check: nix is required" >&2
  exit 1
}

./scripts/test.sh
jq empty schema/roomplan.schema.json
nvim --headless -u NONE -i NONE -n \
  --cmd "set runtimepath^=$ROOT" \
  -c "helptags $ROOT/doc" \
  -c "silent help roomplan" \
  -c "lua assert(vim.bo.filetype == 'help')" \
  -c "qa!"
nvim --headless -u "$ROOT/scripts/minimal_init.lua" -i NONE -n \
  -c "checkhealth roomplan" \
  -c "qa!"
./scripts/benchmark.sh
nix flake check "path:$ROOT" --print-build-logs
git diff --check

echo "release-check: local automated checks passed"
