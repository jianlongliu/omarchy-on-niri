#!/bin/sh
# Drive the greeter against a fake greetd and assert what happened.
#
#   ./tests/smoke.sh
#
# Everything here runs inside the current session: it starts the greeter shell
# against mock-greetd.py instead of GREETD_SOCK, so nothing logs you out and
# /etc is not touched. The greeter takes exclusive keyboard focus for a few
# seconds per case.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Default: the checkout. GREETER=/etc/greetd/split-greeter smokes the installed
# copy instead (its shell and its bridge), which is what greetd actually runs.
GREETER=${GREETER:-$(CDPATH= cd -- "$HERE/.." && pwd)}
MOCK=$HERE/../bridge/mock-greetd.py
BRIDGE=$GREETER/bridge/greetd-bridge.py
WALLPAPER=${WALLPAPER:-$HOME/.local/state/omarchy/current/theme/backgrounds/1-totoro.webp}

# The greeter looks in /var/lib/greeter/users/<account> for the selected
# account's palette and wallpaper. The test cannot write there, so point it at
# a scratch copy of this account's real artwork.
STATE=$HOME/.local/state/omarchy/current
ACCOUNTS=$(mktemp -d)
for account in jianlongliu yvonne; do
  install -d "$ACCOUNTS/$account"
  ln -sfn "$STATE/theme" "$ACCOUNTS/$account/theme"
  ln -sfn "$(readlink -f "$STATE/background" 2>/dev/null || echo "$WALLPAPER")" \
    "$ACCOUNTS/$account/wallpaper"
done
export GREETER_ACCOUNTS_DIR=$ACCOUNTS

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

run_case() { # name, mock user, mock flags, selftest env, want started, expect timeout
  name=$1; user=$2; flags=$3; selftest=$4; want_started=$5; use_timeout=${6:-no}
  dir=$(mktemp -d)
  mkdir -p "$dir/home"
  # shellcheck disable=SC2086
  python3 "$MOCK" --socket "$dir/mock.sock" --user "$user" --password hunter2 \
    --log "$dir/start.log" --pidfile "$dir/mock.pid" $flags >"$dir/mock.out" 2>&1 &
  mock=$!
  trap 'kill "$mock" 2>/dev/null || true' EXIT
  while [ ! -S "$dir/mock.sock" ]; do sleep 0.1; done

  # shellcheck disable=SC2086
  if [ "$use_timeout" = yes ]; then
    set +e
      env HOME="$dir/home" GREETD_SOCK="$dir/mock.sock" GREETER_BRIDGE="$BRIDGE" GREETER_USER=jianlongliu \
      GREETER_ACCOUNTS_DIR="$ACCOUNTS" GREETER_CORNER_RADIUS=10 GREETER_FACE=1 $selftest \
      timeout 8 qs -n -p "$GREETER" >"$dir/run.log" 2>&1
    code=$?
    set -e
  else
    env HOME="$dir/home" GREETD_SOCK="$dir/mock.sock" GREETER_BRIDGE="$BRIDGE" GREETER_USER=jianlongliu \
      GREETER_ACCOUNTS_DIR="$ACCOUNTS" GREETER_CORNER_RADIUS=10 GREETER_FACE=1 $selftest \
      timeout 40 qs -n -p "$GREETER" >"$dir/run.log" 2>&1
    code=$?
  fi

  kill "$(cat "$dir/mock.pid")" 2>/dev/null || true

  started=0
  [ -f "$dir/start.log" ] && started=$(grep -c start_session "$dir/start.log")
  note "-- $name" ""
  if [ "$want_started" = yes ]; then
    check "session handed to greetd" "$started" 1
    check "greeter exited cleanly" "$code" 0
  else
    check "no session handed to greetd" "$started" 0
  fi
  if grep -q ' ERROR' "$dir/run.log"; then
    check "no QML errors" "$(grep -m1 ' ERROR' "$dir/run.log")" ""
  else
    note "no QML errors" ok
  fi
  cp "$dir/run.log" "/tmp/greeter-smoke-$name.log" 2>/dev/null || true
  rm -rf "$dir"
}

# A person typing: keys are injected with wtype into the greeter's own field,
# which is the path a real login takes. The selftest hooks drive the design's
# signals directly, so they cannot see whether the host wired them up — which is
# exactly how "pressing Enter does nothing" shipped: shell.qml was missing
# onPasswordTextEdited, so the field filled with dots while lock.passwordText
# stayed empty, and Enter fell through to "retry the face scan". Needs a
# graphical session with wtype.
run_key_case() { # name, mode (password | switch)
  name=$1; mode=$2
  if ! command -v wtype >/dev/null 2>&1; then
    note "-- $name" "skipped (no wtype)"
    return
  fi
  dir=$(mktemp -d)
  mkdir -p "$dir/home"
  python3 "$MOCK" --socket "$dir/mock.sock" --user jianlongliu --password hunter2 \
    --log "$dir/start.log" --pidfile "$dir/mock.pid" --howdy-fail >"$dir/mock.out" 2>&1 &
  mock=$!
  trap 'kill "$mock" 2>/dev/null || true' EXIT
  while [ ! -S "$dir/mock.sock" ]; do sleep 0.1; done
  env HOME="$dir/home" GREETD_SOCK="$dir/mock.sock" GREETER_BRIDGE="$BRIDGE" GREETER_USER=jianlongliu \
    GREETER_ACCOUNTS_DIR="$ACCOUNTS" GREETER_CORNER_RADIUS=10 GREETER_FACE=1 \
    timeout 40 qs -n -p "$GREETER" >"$dir/run.log" 2>&1 &
  greeter=$!
  sleep 6                      # the howdy attempt times out into a password prompt
  if [ "$mode" = switch ]; then
    wtype -k Tab; sleep 1.2; wtype -k Down -k Down -k Down; sleep 1; wtype -k Return
    sleep 1.5
    wtype 'hunter2'; sleep 1; wtype -k Return
  else
    wtype 'hunter2'; sleep 1; wtype -k Return
  fi
  sleep 3
  kill "$greeter" 2>/dev/null || true
  kill "$(cat "$dir/mock.pid")" 2>/dev/null || true
  started=0
  [ -f "$dir/start.log" ] && started=$(grep -c start_session "$dir/start.log")
  note "-- $name" ""
  check "keys reached the password field" "$(grep -c 'password field received input' "$dir/run.log")" 1
  if [ "$mode" = switch ]; then
    check "picker chose the other account" "$(grep -c 'account picker chose yvonne' "$dir/run.log")" 1
    check "submitted for the picked account" "$(grep -c 'password submitted for yvonne' "$dir/run.log")" 1
  else
    check "submitted for the greeter user" "$(grep -c 'password submitted for jianlongliu' "$dir/run.log")" 1
  fi
  check "session handed to greetd" "$started" 1
  if grep -q ' ERROR' "$dir/run.log"; then
    check "no QML errors" "$(grep -m1 ' ERROR' "$dir/run.log")" ""
  else
    note "no QML errors" ok
  fi
  cp "$dir/run.log" "/tmp/greeter-smoke-$name.log" 2>/dev/null || true
  rm -rf "$dir"
}

run_case "howdy-match"      jianlongliu "--howdy"    "GREETER_AUTOBEGIN=1"        yes
run_case "howdy-miss+pass"  jianlongliu "--howdy-fail --delay 2" "GREETER_AUTOBEGIN=1 GREETER_SELFTEST_PASSWORD=hunter2" yes
run_case "wrong-password"   jianlongliu ""           "GREETER_AUTOBEGIN=1 GREETER_SELFTEST_PASSWORD=wrong"    no yes
run_case "switch-account"   yvonne      "--howdy"    "GREETER_AUTOBEGIN=1 GREETER_SELFTEST_PASSWORD=x GREETER_SELFTEST_PICK=yvonne" yes

# Enter on an empty field is what asks for a face now. Run with the default
# (no GREETER_AUTOBEGIN), so a pass proves nothing scans until asked.
run_enter_face_case() {
  if ! command -v wtype >/dev/null 2>&1; then note "-- enter-triggers-face" "skipped (no wtype)"; return; fi
  dir=$(mktemp -d)
  mkdir -p "$dir/home"
  python3 "$MOCK" --socket "$dir/mock.sock" --user jianlongliu --password hunter2 \
    --log "$dir/start.log" --pidfile "$dir/mock.pid" --howdy >"$dir/mock.out" 2>&1 &
  mock=$!
  trap 'kill "$mock" 2>/dev/null || true' EXIT
  while [ ! -S "$dir/mock.sock" ]; do sleep 0.1; done
  env HOME="$dir/home" GREETD_SOCK="$dir/mock.sock" GREETER_BRIDGE="$BRIDGE" GREETER_USER=jianlongliu \
    GREETER_ACCOUNTS_DIR="$ACCOUNTS" GREETER_CORNER_RADIUS=10 GREETER_FACE=1 \
    timeout 40 qs -n -p "$GREETER" >"$dir/run.log" 2>&1 &
  greeter=$!
  sleep 5
  check "nothing scans unasked" "$(grep -c 'starting a passwordless' "$dir/run.log")" 0
  wtype -k Return
  sleep 4
  kill "$greeter" 2>/dev/null || true
  kill "$(cat "$dir/mock.pid")" 2>/dev/null || true
  note "-- enter-triggers-face" ""
  check "Enter starts the face attempt" "$(grep -c 'starting a passwordless' "$dir/run.log")" 1
  check "session handed to greetd" "$(grep -c start_session "$dir/start.log" 2>/dev/null || echo 0)" 1
  if grep -q ' ERROR' "$dir/run.log"; then check "no QML errors" "$(grep -m1 ' ERROR' "$dir/run.log")" ""; else note "no QML errors" ok; fi
  cp "$dir/run.log" "/tmp/greeter-smoke-enter-face.log" 2>/dev/null || true
  rm -rf "$dir"
}

run_enter_face_case
run_key_case "typed-password" password
run_key_case "typed-switch"    switch

rm -rf "$ACCOUNTS"

echo
echo "FAILURES: $failures"
[ "$failures" -eq 0 ]
