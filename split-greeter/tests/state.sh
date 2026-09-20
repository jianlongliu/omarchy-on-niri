#!/bin/sh
# Regression tests for the login state machine, without a compositor.
#
#   ./tests/state.sh
#
# Drives StateTest.qml (Greetd.qml alone, no design, offscreen) against
# mock-greetd.py. Unlike tests/smoke.sh this needs no Wayland session, so it is
# the suite to run from a TTY — after a wedged login, for instance.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GREETER=${GREETER:-$(CDPATH= cd -- "$HERE/.." && pwd)}
MOCK=$HERE/../bridge/mock-greetd.py

# The picker lists the machine's real human accounts (Users.qml reads /etc/passwd),
# so the fixtures must be accounts that exist here: the first two, overridable.
MAINUSER=${MAINUSER:-$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')}
DEVUSER=${DEVUSER:-$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' | sed -n 2p)}
: "${MAINUSER:?no human account on this machine to test with}"
BRIDGE=$GREETER/bridge/greetd-bridge.py

failures=0
note() { printf '%-34s %s\n' "$1" "$2"; }

check() { # label, got, want
  if [ "$2" = "$3" ]; then
    note "$1" ok
  else
    note "$1" "FAIL (got '$2', want '$3')"
    failures=$((failures + 1))
  fi
}

check_logged() { # label, pattern, want, file
  if grep -q "$2" "$4"; then got=yes; else got=no; fi
  check "$1" "$got" "$3"
}

run_case() { # name, account, mock flags, state env, want started, want helper restart, run for, want face attempts
  name=$1; account=$2; flags=$3; stateenv=$4; want=$5; want_restart=$6; run_for=$7
  want_faces=${8:-}
  dir=$(mktemp -d)
  # shellcheck disable=SC2086
  python3 "$MOCK" --socket "$dir/mock.sock" --user "$account" --password hunter2 \
    --log "$dir/start.log" --pidfile "$dir/mock.pid" $flags >"$dir/mock.out" 2>&1 &
  while [ ! -S "$dir/mock.sock" ]; do sleep 0.1; done

  set +e
  # shellcheck disable=SC2086
  env QT_QPA_PLATFORM=offscreen GREETD_SOCK="$dir/mock.sock" GREETER_BRIDGE="$BRIDGE" \
    GREETER_USER="$account" GREETER_STATE_USER="$account" $stateenv \
    timeout "$run_for" qs -n -p "$GREETER/StateTest.qml" >"$dir/run.log" 2>&1
  code=$?
  set -e

  kill "$(cat "$dir/mock.pid")" 2>/dev/null || true

  started=0
  [ -f "$dir/start.log" ] && started=$(grep -c start_session "$dir/start.log")
  note "-- $name" ""
  if [ "$want" = yes ]; then
    check "session handed to greetd" "$started" 1
    check "greeter exited cleanly" "$code" 0
  else
    check "no session handed to greetd" "$started" 0
  fi
  check_logged "stalled attempt was dropped" "restarting the login helper" "$want_restart" "$dir/run.log"
  if [ -n "$want_faces" ]; then
    # Counting the attempts is the whole point of the double-Enter case: a second
    # one is not a retry, it is a second conversation greetd does not have room
    # for (and on greetd 0.10.3, before the bridge cancelled first, it wedged the
    # login screen for the rest of the boot).
    check "face attempts started" "$(grep -c 'starting a passwordless (face) attempt' "$dir/run.log")" "$want_faces"
  fi
  if grep -q ' ERROR' "$dir/run.log"; then
    check "no QML errors" "$(grep -m1 ' ERROR' "$dir/run.log")" ""
  else
    note "no QML errors" ok
  fi
  cp "$dir/run.log" "/tmp/greeter-state-$name.log" 2>/dev/null || true
  rm -rf "$dir"
}

# A face scan that resolves on its own (howdy match) still logs in.
run_case "howdy-match" "$MAINUSER" "--howdy" "" yes no 15

# Enter hammered while the first attempt is still waiting on PAM (the face missed
# and the secret prompt is up): the second request must be dropped, not turned
# into a second conversation -- greetd has room for exactly one, and the second
# one is what wedged the login screen on 2026-09-20.
run_case "double-face-request" "$MAINUSER" "--howdy-fail" \
  "GREETER_STATE_EXTRA_FACE_MS=1200 GREETER_STATE_DELAY_MS=2500 GREETER_STATE_PASSWORD=hunter2" \
  yes no 15 1

# A wrong password must not hand greetd a session.
run_case "wrong-password" "$MAINUSER" "" "GREETER_STATE_PASSWORD=wrong" no no 6

# The failure that stranded the login screen: PAM never answers the face scan, so
# a typed password was written into a conversation greetd was still holding and
# did nothing. Typing now drops the connection and answers on a fresh one.
run_case "stalled+typed-password" "$MAINUSER" "--hang-face 8" \
  "GREETER_ATTEMPT_TIMEOUT_MS=30000 GREETER_STATE_PASSWORD=hunter2" yes yes 20

# Same wedge with nobody typing: the watchdog frees the screen by itself, so the
# password typed afterwards is the first thing greetd hears.
run_case "stalled+watchdog" "$MAINUSER" "--hang-face 8" \
  "GREETER_ATTEMPT_TIMEOUT_MS=2500 GREETER_STATE_PASSWORD=hunter2 GREETER_STATE_DELAY_MS=5000" yes yes 25

# Switching accounts while the first account's scan is wedged must not leave the
# login for the wrong user hanging.
run_case "switch-during-stall" "$DEVUSER" "--hang-face 8" \
  "GREETER_ATTEMPT_TIMEOUT_MS=30000 GREETER_STATE_USER=$MAINUSER GREETER_STATE_SWITCH=$DEVUSER GREETER_STATE_PASSWORD=hunter2" yes yes 25

# Nobody types at all: the screen recovers (helper restarted) but no session is
# handed over until a password is entered.
run_case "stalled+nothing-typed" "$MAINUSER" "--hang-face 8" "GREETER_ATTEMPT_TIMEOUT_MS=2000" no yes 7

echo
echo "FAILURES: $failures"
[ "$failures" -eq 0 ]
