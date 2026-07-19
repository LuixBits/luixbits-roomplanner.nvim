#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 vMAJOR.MINOR.PATCH[-PRERELEASE]" >&2
  exit 2
fi

tag=$1
if ! printf '%s\n' "$tag" \
  | grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'; then
  echo "release-notes: expected a SemVer tag beginning with v, got: $tag" >&2
  exit 2
fi

version=${tag#v}
awk -v version="$version" '
  BEGIN {
    prefix = "## [" version "]"
  }
  index($0, prefix) == 1 {
    found = 1
    next
  }
  found && /^## \[/ {
    exit
  }
  found {
    lines[++count] = $0
    if ($0 ~ /[^[:space:]]/) content = 1
  }
  END {
    if (!found) {
      print "release-notes: CHANGELOG.md has no section for " version > "/dev/stderr"
      exit 1
    }
    if (!content) {
      print "release-notes: changelog section for " version " is empty" > "/dev/stderr"
      exit 1
    }
    for (i = 1; i <= count; i++) print lines[i]
  }
' CHANGELOG.md
