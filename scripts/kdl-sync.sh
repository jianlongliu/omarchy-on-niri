#!/bin/sh
# The seven niri configs are authored on the machine (~/.config/niri/*.kdl, home directory as a real
# path) and collected in niri-config/local/ with the home directory replaced by /home/<user>, because
# niri does not expand $HOME. That substitution is the ONLY difference for six of the seven, so this
# transforms the machine copies the same way and compares byte for byte.
#
# layout.kdl is the exception: omarchy-niri-apply-theme rewrites its focus-ring / border colours from
# the current theme (and toggles border's bare `on`/`off` to match), so those lines legitimately change
# on every theme *or* wallpaper switch -- matugen re-derives the palette and the hook re-applies it.
# They are dropped from both sides before the compare; everything else in layout.kdl is still compared
# byte for byte, so a hand edit anywhere outside that block still fails the check.
#
# Skipped on a machine without ~/.config/niri (a fresh checkout). Override the machine directory with
# NIRI_CONFIG_DIR=/path and the placeholder with PLACEHOLDER=/home/you.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NIRI=${NIRI_CONFIG_DIR:-$HOME/.config/niri}
PLACEHOLDER=${PLACEHOLDER:-/home/<user>}
fail=0
tmp=$(mktemp)
tmp2=$(mktemp)
trap 'rm -f "$tmp" "$tmp2"' EXIT INT TERM

# Theme-generated keys, plus the bare flag inside `border { }`. Only layout.kdl has them.
generated='^[[:space:]]*((active|inactive)-(color|gradient)([[:space:]]|$)|(on|off)[[:space:]]*$)'
normalise() { # <file name without .kdl>
  if [ "$1" = layout ]; then
    grep -v -E "$generated"
  else
    cat
  fi
}

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
  sed "s|$HOME|$PLACEHOLDER|g" "$src" | normalise "$f" > "$tmp"
  normalise "$f" < "$dst" > "$tmp2"
  if cmp -s "$tmp" "$tmp2"; then
    echo "ok    $f.kdl"
  else
    echo "DIFF  $f.kdl -- machine copy (home path substituted) != repo copy:"
    diff "$tmp" "$tmp2" | head -8
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "niri configs drifted -- re-run the sed in niri-config/README.md and commit" >&2
  exit 1
fi

echo "niri-config/local matches the machine's config"
