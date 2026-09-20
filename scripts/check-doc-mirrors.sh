#!/bin/sh
# The port's big docs are written as a machine-local original plus a repo mirror that has to stay
# byte-identical, otherwise the two drift and nobody notices until someone reads the wrong one.
#
#   ~/Documents/omarchy-on-niri.md        <->  docs/omarchy-on-niri-port.md
#   ~/Documents/omarchy-niri-lock.md      <->  docs/lock.md
#   ~/Documents/omarchy-niri-overrides.md <->  docs/local-overrides.md
#   ~/Documents/omarchy-niri-plugins.md   <->  docs/plugins.md
#
# Run before committing a doc change. On a machine that has no ~/Documents copies (a fresh
# checkout) each pair is skipped rather than failed. Override the originals' directory with
# DOCS_DIR=/path/to/dir.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DOCS=${DOCS_DIR:-$HOME/Documents}
fail=0

check() {
  src=$DOCS/$1
  dst=$ROOT/$2
  if [ ! -f "$src" ]; then
    echo "skip  $1 (no original at $src)"
    return 0
  fi
  if [ ! -f "$dst" ]; then
    echo "DRIFT $1 exists but $2 does not"
    fail=1
    return 0
  fi
  a=$(md5sum "$src" | cut -d' ' -f1)
  b=$(md5sum "$dst" | cut -d' ' -f1)
  if [ "$a" = "$b" ]; then
    echo "ok    $1 == $2"
  else
    echo "DRIFT $1 ($a) != $2 ($b)"
    fail=1
  fi
}

check omarchy-on-niri.md docs/omarchy-on-niri-port.md
check omarchy-niri-lock.md docs/lock.md
check omarchy-niri-overrides.md docs/local-overrides.md
check omarchy-niri-plugins.md docs/plugins.md

if [ "$fail" -ne 0 ]; then
  echo "doc mirrors drift -- copy the original over the mirror (cp -p), then re-run" >&2
  exit 1
fi

echo "all doc mirrors in sync"
