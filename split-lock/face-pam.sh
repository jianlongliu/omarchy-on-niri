#!/bin/bash
# Lock-screen face authentication (howdy) -- the root half of split-lock.
#
#   sudo ./face-pam.sh            write /etc/pam.d/omarchy-lock-face
#   sudo ./face-pam.sh --remove   take it back out
#   ./face-pam.sh --dry-run       say what it would do, change nothing
#
# Rollback is one file: rm /etc/pam.d/omarchy-lock-face. The lock then probes
# faceConfigured to "no" on its next start and hides the face affordance; the
# password path is untouched either way, because this is a *separate* PAM
# service from omarchy-lock-password.
#
# Module order mirrors /etc/pam.d/greetd, which is the same stack this machine
# logs in with: ir-light lights the ThinkPad IR lamp (optional, never fatal),
# howdy decides. howdy has to be the only auth module here: on a miss or with
# no model it returns an error, and the lock's own face PamContext turns that
# into "type your password" rather than a retry loop.
set -euo pipefail

PAM=/etc/pam.d/omarchy-lock-face
HOWDY=/lib/security/howdy/pam.py

dry=0
remove=0
for arg in "$@"; do
  case $arg in
  --dry-run) dry=1 ;;
  --remove) remove=1 ;;
  *) printf 'unknown option: %s\n' "$arg"; exit 2 ;;
  esac
done

run() { if ((dry)); then printf '  would: %s\n' "$*"; else "$@"; fi; }

if ((EUID != 0)); then
  printf '%s\n' "face-pam.sh: needs root (pkexec $0)"; exit 1
fi

if ((remove)); then
  run rm -f "$PAM"
  printf '%s\n' "removed $PAM (the lock hides its face affordance on next start)"
  exit 0
fi

echo "== checks"
if [[ -f $HOWDY ]]; then
  echo "  howdy pam module present: $HOWDY"
else
  echo "  WARNING: no $HOWDY -- without it this service can only fail."
  echo "           Install howdy (pacman -S howdy) and enrol a face first:"
  echo "             sudo howdy add"
fi
if [[ -f /usr/local/bin/ir-light ]]; then
  echo "  ir-light present: /usr/local/bin/ir-light"
else
  echo "  NOTE: no /usr/local/bin/ir-light -- the IR lamp stays dark, so face"
  echo "        auth in a dim room may report 'image too dark'. Writing the"
  echo "        helper into the stack anyway; install the lamp helper when you"
  echo "        want it (see the port docs, §11 greeter section)."
fi
echo "  models: $(ls /usr/lib/security/howdy/models/*.dat 2>/dev/null | tr '\n' ' ')"

echo "== write $PAM"
if ((dry)); then
  printf '  would write %s with:\n' "$PAM"
  printf '    auth optional pam_exec.so /usr/local/bin/ir-light\n'
  printf '    auth required pam_python.so %s\n' "$HOWDY"
  exit 0
fi

cat > "$PAM" <<EOF
#%PAM-1.0
# Lock-screen face authentication (howdy), driven by the lock's own face
# PamContext as a service separate from omarchy-lock-password: a slow or stuck
# scan can then never block the password path. Same module order as
# /etc/pam.d/greetd (ir-light lights the IR lamp, howdy decides).
# Written by split-lock/face-pam.sh -- edit that, not this file.
auth       optional                    pam_exec.so /usr/local/bin/ir-light
auth       required                    pam_python.so $HOWDY
account    include                     system-local-login
EOF
chmod 644 "$PAM"
echo "  wrote $PAM"

echo
echo "Test the stack without locking the session:"
echo "  pamtester omarchy-lock-face \$USER authenticate"
