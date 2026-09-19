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

run_case() { # name, account, mock flags, state env, want started, want helper restart, run for
  name=$1; account=$2; flags=$3; stateenv=$4; want=$5; want_restart=$6; run_for=$7
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
  if grep -q ' ERROR' "$dir/run.log"; then
    check "no QML errors" "$(grep -m1 ' ERROR' "$dir/run.log")" ""
  else
    note "no QML errors" ok
  fi
  cp "$dir/run.log" "/tmp/greeter-state-$name.log" 2>/dev/null || true
  rm -rf "$dir"
}

# A face scan that resolves on its own (howdy match) still logs in.
run_case "howdy-match" jianlongliu "--howdy" "" yes no 15

# A wrong password must not hand greetd a session.
run_case "wrong-password" jianlongliu "" "GREETER_STATE_PASSWORD=wrong" no no 6

# The failure that stranded the login screen: PAM never answers the face scan, so
# a typed password was written into a conversation greetd was still holding and
# did nothing. Typing now drops the connection and answers on a fresh one.
run_case "stalled+typed-password" jianlongliu "--hang-face 300" \
  "GREETER_ATTEMPT_TIMEOUT_MS=30000 GREETER_STATE_PASSWORD=hunter2" yes yes 20

# Same wedge with nobody typing: the watchdog frees the screen by itself, so the
# password typed afterwards is the first thing greetd hears.
run_case "stalled+watchdog" jianlongliu "--hang-face 300" \
  "GREETER_ATTEMPT_TIMEOUT_MS=2500 GREETER_STATE_PASSWORD=hunter2 GREETER_STATE_DELAY_MS=5000" yes yes 25

# Switching accounts while the first account's scan is wedged must not leave the
# login for the wrong user hanging.
run_case "switch-during-stall" yvonne "--hang-face 300" \
  "GREETER_ATTEMPT_TIMEOUT_MS=30000 GREETER_STATE_USER=jianlongliu GREETER_STATE_SWITCH=yvonne GREETER_STATE_PASSWORD=hunter2" yes yes 25

# Nobody types at all: the screen recovers (helper restarted) but no session is
# handed over until a password is entered.
run_case "stalled+nothing-typed" jianlongliu "--hang-face 300" "GREETER_ATTEMPT_TIMEOUT_MS=2000" no yes 7

echo
echo "FAILURES: $failures"
[ "$failures" -eq 0 ]
