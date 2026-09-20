#!/bin/sh
# Every volume has exactly one copy, and it lives in the repo. The machine-local names under
# ~/Documents are symlinks into docs/, so there is nothing left to keep in sync -- but a link can
# be replaced by a real file by accident, and then the two copies drift silently.
#
#   ~/Documents/omarchy-on-niri.md         ->  docs/omarchy-on-niri-port.md   (main: current facts)
#   ~/Documents/omarchy-niri-visual.md     ->  docs/visual.md
#   ~/Documents/omarchy-niri-behavior.md   ->  docs/behavior.md
#   ~/Documents/omarchy-niri-plugins.md    ->  docs/plugins.md
#   ~/Documents/omarchy-niri-shims.md      ->  docs/shims.md
#   ~/Documents/omarchy-niri-upstream.md   ->  docs/upstream.md
#   ~/Documents/omarchy-niri-migration.md  ->  docs/migration.md
#   ~/Documents/omarchy-niri-lock.md       ->  docs/lock.md
#   ~/Documents/omarchy-niri-overrides.md  ->  docs/local-overrides.md
#
# Run before committing a doc change. On a machine with no ~/Documents copies (a fresh checkout)
# each name is skipped rather than failed. Override the directory with DOCS_DIR=/path/to/dir.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DOCS=${DOCS_DIR:-$HOME/Documents}
fail=0

check() {
  link=$DOCS/$1
  want=$ROOT/$2
  if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    echo "skip  $1 (no ~/Documents copy on this machine)"
    return 0
  fi
  if [ ! -e "$want" ]; then
    echo "MISSING $1 points at $2, which is not there"
    fail=1
    return 0
  fi
  if [ ! -L "$link" ]; then
    echo "COPY  $1 is a real file, not a symlink -- the two copies can drift"
    fail=1
    return 0
  fi
  got=$(readlink -f -- "$link" 2>/dev/null || true)
  if [ "$got" != "$(readlink -f -- "$want")" ]; then
    echo "OFF   $1 -> ${got:-<broken link>} (want $2)"
    fail=1
    return 0
  fi
  echo "ok    $1 -> $2"
}

check omarchy-on-niri.md docs/omarchy-on-niri-port.md
check omarchy-niri-visual.md docs/visual.md
check omarchy-niri-behavior.md docs/behavior.md
check omarchy-niri-plugins.md docs/plugins.md
check omarchy-niri-shims.md docs/shims.md
check omarchy-niri-upstream.md docs/upstream.md
check omarchy-niri-migration.md docs/migration.md
check omarchy-niri-lock.md docs/lock.md
check omarchy-niri-overrides.md docs/local-overrides.md

if [ "$fail" -ne 0 ]; then
  echo "doc links are off -- see above; a stale copy should be 'ln -sfn' back into docs/" >&2
  exit 1
fi

echo "all doc links point into docs/"
