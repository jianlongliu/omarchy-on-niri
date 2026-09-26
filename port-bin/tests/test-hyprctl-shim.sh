#!/bin/bash
# Contract test for the hyprctl->niri shim. `niri` and `loginctl` are faked, so
# nothing here can touch the real session, the real displays, or logind.
#
# It is *not* hermetic, though: the last three cases drive the real upstream
# consumer `omarchy-hyprland-session-locked` (that is the point -- asserting the
# shim's output against the actual thing that reads it), and it needs `jq`.
# Both must be on PATH. With a stripped PATH (`env PATH=/usr/bin:/bin ...`)
# those three fail with 127, which says nothing about the shim.
#
# What is under test is the two fields the Omarchy lock layer reads out of
# `hyprctl -j monitors` and never got on niri: dpmsStatus (which the stock lock
# turns into "is this screen blank") and solitaryBlockedBy (which is how
# omarchy-hyprland-session-locked recognises an active session lock). The last
# section covers `disabled` -- the field the clamshell path branches on -- and the
# `hl.monitor({ disabled })` verb behind it, which is implemented as an optional
# include (`output-toggle-off.kdl`) rather than a runtime `niri msg output off`.
# That section points XDG_CONFIG_HOME at the temp dir, so it can never reach the
# real ~/.config/niri, let alone the real screen. The section after it covers
# `hl.monitor({ scale })` -- the Display panel's SCALE row -- where the contract is
# the opposite: a plain runtime `niri msg output … scale` and no file of any kind
# (routing it through a config include once cost this machine its custom modeline).
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
# niri validate -c <file>  |  niri msg [-j] <query...>  |  niri msg action <action...>
# `validate` is not a `msg` subcommand, so it is handled before that guard.
if [[ $1 == validate ]]; then
  shift
  echo "validate $*" >>"$NIRI_ACTIONS"
  exit "${FAKE_NIRI_VALIDATE_RC:-0}"
fi
[[ $1 == msg ]] || exit 1
shift
json=0
[[ $1 == -j || $1 == --json ]] && { json=1; shift; }
case $1 in
action)
  shift
  echo "action $*" >>"$NIRI_ACTIONS"
  exit "${FAKE_NIRI_RC:-0}"
  ;;
outputs)
  # `logical` is null exactly when niri has an output switched off (there is no
  # `enabled` field in `niri msg --json outputs`). FAKE_NIRI_OFF / _EXTERNAL /
  # _EXTERNAL_OFF stage the three states a clamshell decision has to tell apart.
  emit() { # <name> on|off
    if [[ $2 == on ]]; then
      printf '"%s":{"name":"%s","make":"Fake","model":"Fake","serial":null,"physical_size":[0,0],"current_mode":0,"modes":[{"width":2560,"height":1600,"refresh_rate":60000}],"logical":{"x":0,"y":0,"width":1280,"height":800,"scale":2.0,"transform":"Normal"},"vrr_enabled":false,"vrr_supported":false,"is_custom_mode":false}' "$1" "$1"
    else
      printf '"%s":{"name":"%s","make":"Fake","model":"Fake","serial":null,"physical_size":[0,0],"current_mode":null,"modes":[{"width":2560,"height":1600,"refresh_rate":60000}],"logical":null,"vrr_enabled":false,"vrr_supported":false,"is_custom_mode":false}' "$1" "$1"
    fi
  }
  body=$(emit eDP-1 "$([[ -n ${FAKE_NIRI_OFF:-} ]] && echo off || echo on)")
  if [[ -n ${FAKE_NIRI_EXTERNAL:-} ]]; then
    body="$body,$(emit DP-1 "$([[ -n ${FAKE_NIRI_EXTERNAL_OFF:-} ]] && echo off || echo on)")"
  fi
  printf '{%s}\n' "$body"
  exit 0
  ;;
workspaces | focused-output) [[ $json == 1 ]] && echo '{}' || exit 1 ;;
output)
  # `niri msg output <name> <key> <value>` -- one key per call (see the shim).
  shift
  echo "output $*" >>"$NIRI_ACTIONS"
  exit 0
  ;;
*) [[ $json == 1 ]] && echo '{}' || exit 1 ;;
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

echo "== dispatch translates to niri's real argument shapes"
# niri 26.04 dropped the `--` separator: `focus-window` and `close-window` take
# `--id`, while `focus-workspace` / `move-window-to-workspace` take a positional
# reference. Getting this wrong used to send every focus/close dispatch to an
# exit-2 "unexpected argument" that the shim then swallowed.
: >"$NIRI_ACTIONS"
hyprctl dispatch 'hl.dsp.focus({ window = "address:0x10" })' >/dev/null 2>&1
check "lua focus window -> --id" "$(cat "$NIRI_ACTIONS")" "action focus-window --id 16"

: >"$NIRI_ACTIONS"
hyprctl dispatch focuswindow "0x10" >/dev/null 2>&1
check "legacy focuswindow -> --id" "$(cat "$NIRI_ACTIONS")" "action focus-window --id 16"

: >"$NIRI_ACTIONS"
hyprctl dispatch 'hl.dsp.window.close({ window = "address:0x10" })' >/dev/null 2>&1
check "close by address actually closes" "$(cat "$NIRI_ACTIONS")" "action close-window --id 16"

: >"$NIRI_ACTIONS"
hyprctl dispatch 'hl.dsp.window.close({})' >/dev/null 2>&1
check "close with no window -> focused" "$(cat "$NIRI_ACTIONS")" "action close-window"

: >"$NIRI_ACTIONS"
hyprctl dispatch 'hl.dsp.focus({ workspace = "3" })' >/dev/null 2>&1
check "lua focus workspace -> positional" "$(cat "$NIRI_ACTIONS")" "action focus-workspace 3"

: >"$NIRI_ACTIONS"
hyprctl dispatch movetoworkspace 2 >/dev/null 2>&1
check "movetoworkspace -> positional" "$(cat "$NIRI_ACTIONS")" "action move-window-to-workspace 2"

echo "== niri's exit status reaches the caller (upstream's ||-fallbacks need it)"
export FAKE_NIRI_RC=7
hyprctl dispatch 'hl.dsp.focus({ window = "address:0x10" })' >/dev/null 2>&1
check "dispatch propagates niri's failure" "$?" 7
hyprctl dispatch 'no-such-dispatcher-at-all' >/dev/null 2>&1
check "unknown dispatcher is still a safe no-op" "$?" 0
export FAKE_NIRI_RC=0

echo "== hl.monitor({disabled}) -> the output-toggle overlay (the clamshell verb)"
# The overlay path is derived from XDG_CONFIG_HOME, so the real ~/.config/niri is
# never in reach here -- this test cannot switch the actual screen off.
export XDG_CONFIG_HOME="$tmp/cfg"
mkdir -p "$XDG_CONFIG_HOME/niri"
: >"$XDG_CONFIG_HOME/niri/config.kdl"
overlay="$XDG_CONFIG_HOME/niri/output-toggle-off.kdl"

: >"$NIRI_ACTIONS"
FAKE_NIRI_OFF=1 hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })' >/dev/null 2>&1
check "disabled=true writes the overlay" "$(cat "$overlay" 2>/dev/null)" \
  'output "eDP-1" {
    off
}'
check "the overlay is validated against config.kdl" \
  "$(grep -c '^validate -c' "$NIRI_ACTIONS")" 1
check "and reloaded" "$(grep -c '^action load-config-file' "$NIRI_ACTIONS")" 1
check "a null logical reads as disabled" \
  "$(FAKE_NIRI_OFF=1 hyprctl monitors all -j | jq -c '.[0].disabled')" true
check "and as not active" \
  "$(FAKE_NIRI_OFF=1 hyprctl monitors all -j | jq -c '.[0].active')" false
check "omarchy-hyprland-monitor-laptop still names a disabled panel" \
  "$(FAKE_NIRI_OFF=1 omarchy-hyprland-monitor-laptop)" eDP-1

# The clamshell decision reads exactly this field, so let it be the one that answers.
# (Upstream only ever tests the exit status, and `jq -e` exits 4 rather than 1 when
# nothing matches, so the shim's job is "nonzero", not "1".)
ext_active() { FAKE_NIRI_OFF=1 omarchy-hyprland-monitor-external-active >/dev/null 2>&1 && echo yes || echo no; }
check "no external -> external-active says no" \
  "$(FAKE_NIRI_EXTERNAL= ext_active)" no
check "enabled external -> external-active says yes" \
  "$(FAKE_NIRI_EXTERNAL=1 ext_active)" yes
check "external plugged in but niri-disabled -> says no" \
  "$(FAKE_NIRI_EXTERNAL=1 FAKE_NIRI_EXTERNAL_OFF=1 ext_active)" no

# A config niri would reject on reload must not be left behind.
rm -f "$overlay"
check "invalid config -> overlay removed again" \
  "$(FAKE_NIRI_VALIDATE_RC=1 FAKE_NIRI_OFF=1 hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })' >/dev/null 2>&1; \
     [[ -e $overlay ]] && echo present || echo gone)" gone

FAKE_NIRI_OFF=1 hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })' >/dev/null 2>&1
: >"$NIRI_ACTIONS"
hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = false })' >/dev/null 2>&1
check "disabled=false removes the overlay" \
  "$([[ -e $overlay ]] && echo present || echo gone)" gone
check "and re-enabling also reloads" \
  "$(grep -c '^action load-config-file' "$NIRI_ACTIONS")" 1
check "monitors reports it active again" \
  "$(hyprctl monitors all -j | jq -c '.[0].active')" true

# An overlay that belongs to another output is somebody else's state, not ours.
printf 'output "DP-1" {\n    off\n}\n' >"$overlay"
hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = false })' >/dev/null 2>&1
check "does not delete another output's overlay" \
  "$([[ -e $overlay ]] && echo present || echo gone)" present
rm -f "$overlay"

echo "== hl.monitor({scale}) is runtime-only: niri msg output, never a config file"
# The Display panel's SCALE row lands here, and stays a runtime `niri msg output … scale`
# on purpose. Driving it through a leading config include was tried on 2026-09-25 and cost
# this machine its tuned custom modeline: the mode list is built from the *first* block for
# an output, and an overlay block carrying only `scale` has no `modeline` in it, so the
# panel fell back to the 3840x2400 preferred mode for the rest of the session. Persisting
# the value is monitor.kdl's `scale` line instead. XDG_STATE_HOME is pointed at the temp
# dir as well, so a future "remember it" patch could not touch the real state either.
export XDG_STATE_HOME="$tmp/state"
: >"$NIRI_ACTIONS"
hyprctl eval \
  'hl.monitor({ output = "eDP-1", mode = "2560x1600@60.00", position = "auto", scale = 1.25 })' \
  >/dev/null 2>&1
check "scale reaches niri's runtime" \
  "$(grep -c '^output eDP-1 scale 1.25$' "$NIRI_ACTIONS")" 1
check "mode is skipped (niri rejects the WxH@Hz form)" \
  "$(grep -c '^output eDP-1 mode' "$NIRI_ACTIONS")" 0
check "position=auto is not applied" \
  "$(grep -c '^output eDP-1 position' "$NIRI_ACTIONS")" 0
check "no config was written, validated or reloaded" \
  "$(grep -c -E '^(validate|action load-config-file)' "$NIRI_ACTIONS")" 0
check "so ~/.config/niri is untouched" \
  "$(ls "$XDG_CONFIG_HOME/niri" | tr -d '\n')" config.kdl
check "and nothing was remembered behind the user's back" \
  "$([[ -e $XDG_STATE_HOME ]] && echo written || echo nothing)" nothing

echo
echo "checks=$checks failures=$failures"
[[ $failures -eq 0 ]] || exit 1
