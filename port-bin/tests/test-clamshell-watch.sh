#!/bin/bash
# Contract test for the clamshell watcher, offline: the lid, `niri msg`, and the
# reconciler it calls are all fakes, so nothing here suspends, blanks, or switches
# an output. Also nothing here needs a niri session.
#
# The watcher exists because niri has no output events and no switch binds, so the
# only way to notice "lid closed" / "monitor plugged in" is to poll. What is being
# tested is therefore not the clamshell logic (upstream owns that) but the loop's
# contract with it:
#   1. lid open, no change      -> never calls the reconciler
#   2. lid closes               -> calls it once
#   3. same state, next ticks   -> does NOT call it again (change-driven, so it
#                                  cannot fight a user who switched an output by hand)
#   4. an output comes or goes  -> calls it again
#   5. lid opens                -> calls it again
#   6. no lid switch on the box -> exits instead of watching forever
#   7. the off-switch flag      -> exits
#
#   ./tests/test-clamshell-watch.sh
#
# checks=N failures=M, exit 1 on any failure.

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WATCH=$(dirname "$HERE")/omarchy-hyprland-monitor-watch
[[ -f $WATCH ]] || { echo "no watcher at $WATCH"; exit 1; }

checks=0
failures=0
check() { # name got want
  checks=$((checks + 1))
  if [[ "$2" == "$3" ]]; then
    printf '  %-46s ok\n' "$1"
  else
    printf '  %-46s FAIL (got %s, want %s)\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/omarchy/bin" "$tmp/lid/LID0" "$tmp/state"
LIDSTATE="$tmp/lid/LID0/state"  # /proc/acpi/button/lid/<dev>/state shape

# --- fake reconciler: just counts how often the loop asked for a reconcile ------
cat >"$tmp/omarchy/bin/omarchy-hyprland-monitor-clamshell" <<'SH'
#!/bin/bash
echo "reconcile" >>"$RECONCILE_LOG"
SH
chmod +x "$tmp/omarchy/bin/omarchy-hyprland-monitor-clamshell"

# --- fake niri: reports whatever $OUTPUTS_STATE says ---------------------------
cat >"$tmp/bin-niri" <<'SH'
#!/bin/bash
[[ $1 == msg ]] || exit 99
shift
[[ $1 == -j || $1 == --json ]] && shift
case $1 in
outputs)
  case "$(<"$OUTPUTS_STATE")" in
  internal_only) printf '{"eDP-1":%s}\n' "$ON" ;;
  docked) printf '{"DP-1":%s,"eDP-1":%s}\n' "$ON" "$OFF" ;;
  esac
  ;;
*) exit 1 ;;
esac
SH
ON='{"name":"eDP-1","logical":{"x":0,"y":0,"width":1280,"height":800,"scale":2.0}}'
OFF='{"name":"eDP-1","logical":null}'
export ON OFF
mkdir -p "$tmp/path"
install -m 0755 "$tmp/bin-niri" "$tmp/path/niri"

echo closed >"$LIDSTATE"
printf 'internal_only\n' >"$tmp/state/outputs"
export OUTPUTS_STATE="$tmp/state/outputs"
export RECONCILE_LOG="$tmp/reconcile.log"
: >"$RECONCILE_LOG"

export OMARCHY_PATH="$tmp/omarchy"
export OMARCHY_LID_GLOB="$tmp/lid/*/state"
export OMARCHY_CLAMSHELL_POLL=0.2
# Also keeps the watcher's off-switch flag out of the real ~/.local/state.
export XDG_STATE_HOME="$tmp/state"
export PATH="$tmp/path:$PATH"
export NIRI_SOCKET="$tmp/niri.sock"
mkdir -p "$XDG_STATE_HOME/omarchy/toggles"
hash -r

watch() { # start the watcher detached from this shell's job control
  "$WATCH" >"$tmp/watch.log" 2>&1 &
  watch_pid=$!
  sleep 0.5
}

count() { grep -c reconcile "$RECONCILE_LOG"; }

# --- 1. the first tick applies the current state once, then stops --------------
echo open >"$LIDSTATE"
watch
check "startup applies current state once" "$(count)" 1
sleep 0.6
check "and then leaves an unchanged state alone" "$(count)" 1

# --- 2. lid closes: exactly one more call --------------------------------------
echo closed >"$LIDSTATE"
sleep 0.6
check "lid closes -> reconciles once" "$(count)" 2

# --- 3. steady state: no repeats -----------------------------------------------
sleep 0.6
check "unchanged state -> no repeat calls" "$(count)" 2

# --- 4. a monitor appears while the lid is closed ------------------------------
printf 'docked\n' >"$OUTPUTS_STATE"
sleep 0.6
check "monitor appears -> reconciles again" "$(count)" 3

# --- 5. lid opens again ---------------------------------------------------------
echo open >"$LIDSTATE"
sleep 0.6
check "lid opens -> reconciles again" "$(count)" 4

sleep 0.6
check "and then stays quiet" "$(count)" 4

# --- 7. the off switch ---------------------------------------------------------
kill "$watch_pid" 2>/dev/null
wait "$watch_pid" 2>/dev/null
: >"$XDG_STATE_HOME/omarchy/toggles/clamshell-watch-off"

# --- 6. no lid switch on this machine ------------------------------------------
XDG_STATE_HOME="$tmp/empty-state" OMARCHY_LID_GLOB="$tmp/nolid/*/state" timeout 5 "$WATCH"
check "no lid switch -> exits 0" "$?" 0

timeout 5 "$WATCH"
check "off-switch flag -> exits 0" "$?" 0

# --- it says what it did, so journalctl has something to show -------------------
check "reconciles are logged with the reason" \
  "$(grep -c 'lid closed' "$tmp/watch.log")" 2

echo
echo "checks=$checks failures=$failures"
[[ $failures -eq 0 ]] || exit 1
