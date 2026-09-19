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
GREETER=$(dirname "$HERE")
MOCK=$GREETER/bridge/mock-greetd.py
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
  # shellcheck disable=SC2086
  python3 "$MOCK" --socket "$dir/mock.sock" --user "$user" --password hunter2 \
    --log "$dir/start.log" --pidfile "$dir/mock.pid" $flags >"$dir/mock.out" 2>&1 &
  while [ ! -S "$dir/mock.sock" ]; do sleep 0.1; done

  # shellcheck disable=SC2086
  if [ "$use_timeout" = yes ]; then
    set +e
      env GREETD_SOCK="$dir/mock.sock" GREETER_BRIDGE="$BRIDGE" GREETER_USER=jianlongliu \
      GREETER_ACCOUNTS_DIR="$ACCOUNTS" GREETER_CORNER_RADIUS=10 $selftest \
      timeout 8 qs -n -p "$GREETER" >"$dir/run.log" 2>&1
    code=$?
    set -e
  else
    env GREETD_SOCK="$dir/mock.sock" GREETER_BRIDGE="$BRIDGE" GREETER_USER=jianlongliu \
      GREETER_ACCOUNTS_DIR="$ACCOUNTS" GREETER_CORNER_RADIUS=10 $selftest \
      qs -n -p "$GREETER" >"$dir/run.log" 2>&1
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

run_case "howdy-match"      jianlongliu "--howdy"                                   ""    yes
run_case "howdy-miss+pass"  jianlongliu "--howdy-fail --delay 2" "GREETER_SELFTEST_PASSWORD=hunter2" yes
run_case "wrong-password"   jianlongliu ""                          "GREETER_SELFTEST_PASSWORD=wrong"    no yes
run_case "switch-account"   yvonne      "--howdy"                   "GREETER_SELFTEST_PASSWORD=x GREETER_SELFTEST_PICK=yvonne" yes

rm -rf "$ACCOUNTS"

echo
echo "FAILURES: $failures"
[ "$failures" -eq 0 ]
