#!/bin/sh
# The seven niri configs are authored on the machine (~/.config/niri/*.kdl, home directory as a real
# path) and collected in niri-config/local/ with the home directory replaced by /home/<user>, because
# niri does not expand $HOME. That substitution is meant to be the ONLY difference, so this
# transforms the machine copies the same way and compares byte for byte.
#
# Skipped on a machine without ~/.config/niri (a fresh checkout). Override the machine directory with
# NIRI_CONFIG_DIR=/path and the placeholder with PLACEHOLDER=/home/you.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NIRI=${NIRI_CONFIG_DIR:-$HOME/.config/niri}
PLACEHOLDER=${PLACEHOLDER:-/home/<user>}
fail=0
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT INT TERM

for f in config input monitor layout window-rules effects binds; do
  src=$NIRI/$f.kdl
  dst=$ROOT/niri-config/local/$f.kdl
  if [ ! -f "$src" ]; then
    echo "skip  $f.kdl (no machine copy on this machine)"
    continue
  fi
  if [ ! -f "$dst" ]; then
    echo "MISSING niri-config/local/$f.kdl"
    fail=1
    continue
  fi
  sed "s|$HOME|$PLACEHOLDER|g" "$src" > "$tmp"
  if cmp -s "$tmp" "$dst"; then
    echo "ok    $f.kdl"
  else
    echo "DIFF  $f.kdl -- machine copy (home path substituted) != repo copy:"
    diff "$tmp" "$dst" | head -8
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "niri configs drifted -- re-run the sed in niri-config/README.md and commit" >&2
  exit 1
fi

echo "niri-config/local matches the machine's config"
