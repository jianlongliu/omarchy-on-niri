#!/bin/sh
# Contract test for split-lock's LockView, offscreen — no session lock, no risk
# to the running desktop. It proves the wires the stock lock service relies on
# (property bindings, passwordTextEdited / submitPassword / clearFailureRequested
# on the same type) against our Split-based view.
#
# What it does NOT prove: real keystrokes reaching the field end to end. That
# needs a live swap-in, with an escape route verified first.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOCK=$(CDPATH= cd -- "$HERE/.." && pwd)
SHELLMODS=${OMARCHY_SHELL:-$HOME/.local/share/omarchy/shell}

failures=0
note() { printf '%-34s %s\n' "$1" "$2"; }
check() {
  if [ "$2" = "$3" ]; then note "$1" ok; else note "$1" "FAIL (got '$2', want '$3')"; failures=$((failures + 1)); fi
}

if [ ! -d "$SHELLMODS/Commons" ]; then
  echo "tests/state.sh: no qs.Commons at $SHELLMODS (set OMARCHY_SHELL)" >&2
  exit 2
fi
command -v qs >/dev/null 2>&1 || { echo "tests/state.sh: qs not on PATH" >&2; exit 2; }

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
# Assemble a throwaway qs project: the design imports qs.Commons and qs.Ui by
# name, the way it does inside the shell, and a subdirectory with a qmldir
# declaring that module is what makes it resolve standalone. Everything lives
# next to the copied shell.qml so its `import "."` finds LockView.
proj=$dir/project
mkdir -p "$proj"
ln -s "$SHELLMODS/Commons" "$proj/Commons"
ln -s "$SHELLMODS/Ui" "$proj/Ui"
# Flat: in the repo the view and the design files it uses sit side by side, so
# they have to stay side by side here too.
for f in "$LOCK"/*.qml; do cp "$f" "$proj/"; done
cp "$HERE/mockhost/shell.qml" "$proj/shell.qml"

set +e
QT_QPA_PLATFORM=offscreen timeout 40 qs -n -p "$proj/shell.qml" >"$dir/run.log" 2>&1
code=$?
set -e

note "-- lockview-contract" ""
check "shell exited 0" "$code" 0
check "no QML errors" "$(grep -c ' ERROR' "$dir/run.log")" 0
check "no missing-property errors" "$(grep -c 'non-existent property' "$dir/run.log")" 0
check "all contract checks ran" "$(grep -o 'checks=[0-9]*' "$dir/run.log" | tail -1)" "checks=8"
check "zero failures inside" "$(grep -o 'failures=[0-9]*' "$dir/run.log" | tail -1)" "failures=0"

# Always show what the mock actually asserted. "0 ERROR lines" on its own is also
# what a mock that never ran prints, so the count of checks is the real marker.
esc=$(printf '\033')
grep -a 'lockhost: ' "$dir/run.log" | sed "s/${esc}\[[0-9;]*m//g" | sed 's/.*lockhost: /  /'

if [ "$failures" -gt 0 ]; then
  echo
  echo "--- log tail"
  grep -vE '^\s*$' "$dir/run.log" | tail -25
fi
cp "$dir/run.log" /tmp/split-lock-state.log 2>/dev/null || true

echo
if [ "$failures" -gt 0 ]; then echo "FAILURES: $failures"; exit 1; else echo "FAILURES: 0"; fi
