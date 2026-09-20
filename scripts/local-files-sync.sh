#!/bin/sh
# Three families of machine-authored files are collected in this repo, each authored on the machine
# and copied here verbatim:
#
#   local-config/**            <- ~/.config/**            (no substitution: these files carry no home literals)
#   plugins/jianlongliu.*      <- ~/.config/omarchy/plugins/jianlongliu.*   (self-written plugin sources)
#   split-lock/ir-light        <- /usr/local/bin/ir-light
#
# Unlike niri-config/local/ (which is the placeholder version of ~/.config/niri/*.kdl, compared by
# scripts/kdl-sync.sh after a sed), every pair here has to be byte-identical. Anything in this repo
# that has no machine counterpart is skipped, which is what makes the script usable on a fresh
# checkout.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONF=${XDG_CONFIG_HOME:-$HOME/.config}
PLUGINS=$CONF/omarchy/plugins
IR=${IR_LIGHT_PATH:-/usr/local/bin/ir-light}
fail=0

cmp_one() { # <repo file> <machine file> <label>
  if [ ! -f "$2" ]; then
    echo "skip    $3 (no machine copy on this machine)"
    return 0
  fi
  if cmp -s "$1" "$2"; then
    echo "ok      $3"
  else
    echo "DIFF    $3 -- repo copy != machine copy:"
    diff "$2" "$1" | head -8
    fail=1
  fi
}

echo "-- local-config/ (-> ~/.config/)"
for dst in $(cd "$ROOT/local-config" && find . -type f ! -name README.md | sed 's|^\./||' | sort); do
  cmp_one "$ROOT/local-config/$dst" "$CONF/$dst" "local-config/$dst"
done

echo "-- plugins/ (-> ~/.config/omarchy/plugins/)"
for dst in $(cd "$ROOT/plugins" 2>/dev/null && find . -type f ! -name README.md | sed 's|^\./||' | sort); do
  cmp_one "$ROOT/plugins/$dst" "$PLUGINS/$dst" "plugins/$dst"
done

echo "-- split-lock/ir-light (-> /usr/local/bin/ir-light)"
if [ -f "$ROOT/split-lock/ir-light" ]; then
  cmp_one "$ROOT/split-lock/ir-light" "$IR" "split-lock/ir-light"
fi

if [ "$fail" -ne 0 ]; then
  echo "collected files drifted -- copy the machine version over the repo one and commit" >&2
  exit 1
fi

echo "local-config/, plugins/ and split-lock/ir-light match this machine"
