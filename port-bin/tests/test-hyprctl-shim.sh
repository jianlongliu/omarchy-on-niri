#!/bin/bash
# Contract test for the hyprctl->niri shim, offline: fake `niri` and `loginctl`
# so nothing here can touch the real session, the real displays, or logind.
#
# What is under test is the two fields the Omarchy lock layer reads out of
# `hyprctl -j monitors` and never got on niri: dpmsStatus (which the stock lock
# turns into "is this screen blank") and solitaryBlockedBy (which is how
# omarchy-hyprland-session-locked recognises an active session lock).
#
#   ./tests/test-hyprctl-shim.sh
#
# checks=N failures=M, exit 1 on any failure.

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SHIM=$(dirname "$HERE")/hyprctl
[[ -f $SHIM ]] || { echo "no shim at $SHIM"; exit 1; }

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
stub="$tmp/stub"
mkdir -p "$stub"

# --- fake niri: one output, and it records every action it is asked to perform
cat >"$stub/niri" <<'SH'
#!/bin/bash
# niri msg [-j] <query...>  |  niri msg action <action...>
[[ $1 == msg ]] || exit 1
shift
json=0
[[ $1 == -j || $1 == --json ]] && { json=1; shift; }
case $1 in
action)
  shift
  echo "action $*" >>"$NIRI_ACTIONS"
  exit 0
  ;;
outputs)
  cat <<'JSON'
{"eDP-1":{"name":"eDP-1","make":"Fake","model":"Fake","serial":null,
"physical_size":[0,0],"current_mode":0,
"modes":[{"width":2560,"height":1600,"refresh_rate":60000}],
"logical":{"x":0,"y":0,"width":1280,"height":800,"scale":2.0,"transform":"Normal"},
"vrr_enabled":false,"vrr_supported":false,"is_custom_mode":false}}
JSON
  exit 0
  ;;
workspaces | focused-output | *) [[ $json == 1 ]] && echo '{}' || exit 1 ;;
esac
SH
chmod +x "$stub/niri"

# --- fake loginctl: answers LockedHint from $FAKE_LOCKED (yes|no|fail)
cat >"$stub/loginctl" <<'SH'
#!/bin/bash
case "$*" in
*LockedHint*)
  case "${FAKE_LOCKED:-no}" in
  yes) echo yes ;;
  no) echo no ;;
  *) exit 1 ;;
  esac
  ;;
*) exit 1 ;;
esac
SH
chmod +x "$stub/loginctl"
export NIRI_ACTIONS="$tmp/actions"
export FAKE_LOCKED=no

# The real shim, reached by its real name, with the stubs first in PATH.
ln -sf "$SHIM" "$stub/hyprctl"
export XDG_SESSION_ID=1
export XDG_RUNTIME_DIR="$tmp/run"
mkdir -p "$XDG_RUNTIME_DIR"
export PATH="$stub:$PATH"
hash -r

monitors() { hyprctl -j monitors; }

echo "== dpmsStatus tracks what we dispatch (niri IPC has no power state)"
: >"$NIRI_ACTIONS"
rm -f "$XDG_RUNTIME_DIR/hyprctl-shim-dpms"
check "unknown state reads as lit" \
  "$(monitors | jq -c '.[0].dpmsStatus')" true
check "state file really is absent" \
  "$([[ -e $XDG_RUNTIME_DIR/hyprctl-shim-dpms ]] && echo present || echo absent)" absent

hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null
check "blanking forwards to niri" "$(cat "$NIRI_ACTIONS")" "action power-off-monitors"
check "blanking is recorded" "$(monitors | jq -c '.[0].dpmsStatus')" false

hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null
check "unblanking is recorded" "$(monitors | jq -c '.[0].dpmsStatus')" true

hyprctl dispatch dpms off >/dev/null
check "plain 'dispatch dpms off' recorded too" "$(monitors | jq -c '.[0].dpmsStatus')" false
hyprctl dispatch dpms on >/dev/null

echo "== solitaryBlockedBy maps logind's LockedHint onto Hyprland's LOCK"
FAKE_LOCKED=yes
check "locked  -> LOCK" "$(monitors | jq -c '.[0].solitaryBlockedBy')" '["LOCK"]'
FAKE_LOCKED=no
check "unlocked -> no blockers" "$(monitors | jq -c '.[0].solitaryBlockedBy')" '[]'
FAKE_LOCKED=fail
check "no answer -> WORKSPACE (undetermined)" \
  "$(monitors | jq -c '.[0].solitaryBlockedBy')" '["WORKSPACE"]'

echo "== the consumer that needs it: omarchy-hyprland-session-locked"
sl() { omarchy-hyprland-session-locked; echo $?; }
FAKE_LOCKED=yes
check "locked   -> exit 0 (locked)" "$(sl)" 0
FAKE_LOCKED=no
check "unlocked -> exit 1 (unlocked)" "$(sl)" 1
FAKE_LOCKED=fail
check "unknown  -> exit 2 (undetermined)" "$(sl)" 2

echo
echo "checks=$checks failures=$failures"
[[ $failures -eq 0 ]] || exit 1
