#!/bin/bash
# Contract test for the uwsm-app shim, offline: the "app" under test is a stub script
# in a temp dir, so nothing here can start a real application or touch the session.
#
# What is under test is the interface Omarchy's bin/ relies on in ~30 call sites:
# `uwsm-app -- <command> [args...]` must end up running <command> with args intact,
# in a new session (detached), with uwsm-app's own options simply dropped.
#
#   ./tests/test-uwsm-app-shim.sh
#
# checks=N failures=M, exit 1 on any failure.

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SHIM=$(dirname "$HERE")/uwsm-app
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
export STUB_OUT="$tmp/out"

# --- fake "app": records its argv and its session id, nothing else
cat >"$tmp/stub" <<'SH'
#!/bin/bash
{
  printf 'argv=%s\n' "$*"
  printf 'sid=%s\n' "$(ps -o sid= -p $$ | tr -d ' ')"
} >>"$STUB_OUT"
SH
chmod +x "$tmp/stub"

n=0
run_stub() { # <uwsm-app args...> -> waits for the stub, echoes its recorded argv
  n=$((n + 1))
  : >"$STUB_OUT"
  "$SHIM" "$@" >/dev/null 2>&1
  for _ in $(seq 1 40); do
    [[ -s $STUB_OUT ]] && break
    sleep 0.05
  done
  sed -n 's/^argv=//p' "$STUB_OUT"
}

check "argv passes through after --"      "$(run_stub -- "$tmp/stub" a b c)"  "a b c"
check "uwsm-app's own options are dropped" "$(run_stub --app-name=x --unit-name=y -- "$tmp/stub" z)" "z"
check "no -- separator still works"        "$(run_stub "$tmp/stub" q)"         "q"

"$SHIM" -- >/dev/null 2>"$tmp/err"; rc=$?
check "no command: exit code"    "$rc" "1"
check "no command: message"      "$(grep -c 'no command' "$tmp/err")" "1"

"$SHIM" --help >"$tmp/help" 2>&1
check "--help exit code"         "$?" "0"
check "--help prints usage"      "$(grep -c 'Usage: uwsm-app' "$tmp/help")" "1"
"$SHIM" --version >"$tmp/ver" 2>&1
check "--version exit code"      "$?" "0"
check "--version prints name"    "$(grep -c 'uwsm-app' "$tmp/ver")" "1"

# the launched command's exit status must survive the shim (callers check it)
"$SHIM" -- sh -c 'exit 7' >/dev/null 2>&1
check "command exit status propagates" "$?" "7"

# Regression (2026-09-20): under `systemd-run --user` the unit's main process is a
# session leader, so a `setsid` inside the shim would fork-and-exit immediately and
# systemd would then reap the unit's cgroup (KillMode=control-group) — killing the app
# that was just launched (silently: bin/omarchy-launch-browser passes
# --property=StandardError=null; symptom is exit 0 and no window). So the app must stay
# the unit's main process. Still offline: the "app" is the stub, no GUI involved.
cat >"$tmp/sleepy" <<'SH'
#!/bin/bash
echo start >"$STUB_OUT"
sleep 2
echo end >>"$STUB_OUT"
SH
chmod +x "$tmp/sleepy"

if command -v systemd-run >/dev/null && [[ -d ${XDG_RUNTIME_DIR:-/nonexistent} ]]; then
  : >"$STUB_OUT"
  unit="uwsm-shim-selftest-$$"
  systemd-run --user --quiet --collect --unit="$unit" --setenv=STUB_OUT="$STUB_OUT" --wait "$SHIM" -- "$tmp/sleepy" &
  sr=$!
  sleep 1
  check "unit still active while app runs" "$(systemctl --user is-active "$unit.service" 2>/dev/null)" "active"
  wait "$sr"
  check "app survived to completion in the unit" "$(tail -1 "$STUB_OUT" 2>/dev/null)" "end"
else
  echo "  (skipped: no systemd --user session available)"
fi

bash -n "$SHIM" 2>/dev/null
check "shim parses (bash -n)" "$?" "0"

echo
echo "checks=$checks failures=$failures"
[[ $failures -eq 0 ]]
