#!/bin/sh
# The user session command (GREETER_SESSION in niri.kdl).
#
# greetd runs the session with the VT as its stdout/stderr, and those fds are
# only visible once the greeter's compositor has let go of the screen -- which
# is exactly the gap between "password accepted" and "desktop up". Whatever the
# session prints while it starts (niri-session, its login shell, a unit failing)
# therefore lands in the middle of the handoff. So: repaint the console black
# first, and keep the output in a log where it can actually be read afterwards.
#
# The marker tells the shell this is a real login handoff and not a shell
# restart, so the fade-in from black happens once per session.
#
# Nothing in here may cost the login: every step is best effort, and a log that
# cannot be written just means we keep the old (console) behaviour.

# Never trust an inherited XDG_* or HOME here: this runs on the way out of the
# greeter, so the environment can still be the greeter's (its own uid and
# /var/lib/greeter). Both paths below must belong to the account being logged
# in, which is the one this script runs as -- so derive them from that.
home=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)
log="${XDG_STATE_HOME:-${home:-$HOME}/.local/state}/omarchy/session.log"
# The marker is read by the shell of *this* account, i.e. out of this account's
# runtime dir; XDG_RUNTIME_DIR may still point at the greeter's.
runtime="/run/user/$(id -u)"
[ -d "$runtime" ] || runtime="${XDG_RUNTIME_DIR:-$runtime}"

# fd 1 is still the VT here: clear it before anything else can write to it.
printf '\033[2J\033[H' >&1 2>/dev/null

mkdir -p "$(dirname "$log")" 2>/dev/null
: > "$runtime/omarchy-boot-splash" 2>/dev/null

if : >>"$log" 2>/dev/null; then
  exec >>"$log" 2>&1
  # The resolved paths belong in the log: if the marker ever lands somewhere the
  # shell does not look, this line is how that shows up.
  echo "session wrapper: uid=$(id -u) home=${home:-$HOME} runtime=$runtime marker=$runtime/omarchy-boot-splash"
fi

exec niri-session "$@"
