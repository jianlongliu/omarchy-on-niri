#!/bin/bash
# Install Split Lock as an Omarchy shell plugin.
#
# The lock is a "service" plugin, and the shell instantiates `LockView { }` by
# **filename** out of the plugin's own directory. So the swap is: ship
# omarchy's lock service verbatim (Service.qml) plus our LockView.qml and the
# Split design files flat next to it. Nothing in omarchy's tree is touched, and
# no third-party lock plugin is needed.
#
#   ./install.sh              install, then disable the third-party lock plugin
#   ./install.sh --stage      install but leave it disabled, so the lock in use
#                             does not change until you say so
#   ./install.sh --dry-run    say what it would do, change nothing
#
# Rollback (the whole thing is one directory):
#   rm -rf ~/.config/omarchy/plugins/yvonne.split-lock
#   omarchy plugin enable io.github.sirjul1337.lock-explorer
#   omarchy-restart-shell
#
# If the session ever locks with nothing on screen, the way out is a text
# console: switch VT, log in, `systemctl --user restart omarchy-shell`. Killing
# the ext-session-lock client is what releases the lock, so that always works
# even when nothing else does.
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PLUGIN_ID=yvonne.split-lock
THIRD_PARTY_LOCK=io.github.sirjul1337.lock-explorer
DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
OMARCHY=${OMARCHY_PATH:-"$HOME/.local/share/omarchy"}
SOURCE_SERVICE="$OMARCHY/shell/plugins/lock/Service.qml"
LOCK_PAM=/etc/pam.d/omarchy-lock-password

# Service.qml is a verbatim copy of upstream's lock service, the one file that
# has to live in the same directory as LockView.qml. If upstream changes it,
# ours is stale and this hash says so.
EXPECTED_SERVICE_MD5=a2f85612e11c7e2c39cdab0a43e8d9a0

dry=0
stage=0
for arg in "$@"; do
  case $arg in
  --dry-run) dry=1 ;;
  --stage) stage=1 ;;
  *) say_unknown=$arg ;;
  esac
done
[[ -z ${say_unknown:-} ]] || { printf 'unknown option: %s\n' "$say_unknown"; exit 2; }

say() { printf '%s\n' "$*"; }
run() {
  if ((dry)); then say "  would: $*"; else "$@"; fi
}

files=(manifest.json Service.qml LockView.qml
  Split.qml DesignBase.qml LockInput.qml PasswordField.qml Avatar.qml Wallpaper.qml)

for f in "${files[@]}"; do
  [[ -f $HERE/$f ]] || { say "missing $f in $HERE"; exit 1; }
done

say "== checks"
if [[ -f $LOCK_PAM ]]; then
  say "  pam service present: $LOCK_PAM"
else
  say "  WARNING: $LOCK_PAM is missing, so the lock would refuse to engage."
  say "           Run: pkexec $OMARCHY/bin/omarchy-apply-lock"
fi

if [[ -f $SOURCE_SERVICE ]]; then
  actual=$(md5sum "$SOURCE_SERVICE" | cut -d' ' -f1)
  if [[ $actual == "$EXPECTED_SERVICE_MD5" ]]; then
    say "  Service.qml copy is current (matches upstream $EXPECTED_SERVICE_MD5)"
  else
    say "  WARNING: upstream Service.qml changed (ours $EXPECTED_SERVICE_MD5,"
    say "           upstream $actual). Re-copy it and re-run the contract test:"
    say "           cp '$SOURCE_SERVICE' '$HERE/Service.qml' && (cd '$HERE' && ./tests/state.sh)"
  fi
else
  say "  WARNING: no upstream lock service at $SOURCE_SERVICE, is omarchy installed?"
fi

say "== install -> $DEST"
run install -d "$DEST"
for f in "${files[@]}"; do
  run install -m 0644 "$HERE/$f" "$DEST/$f"
done

say "== validate the installed copy"
if ((dry)); then
  say "  would: omarchy plugin validate $DEST"
else
  omarchy plugin validate "$DEST" || {
    say "validate failed; the previous plugin is untouched, clean up with: rm -rf '$DEST'"
    exit 1
  }
fi

# The lock is a singleton: two plugins cloning omarchy.lock would race for it.
if ((stage)); then
  say "== staged: leave it disabled so the lock in use does not change yet"
  run omarchy plugin disable "$PLUGIN_ID"
  say
  say "Activate it when you are ready to test, in one step:"
  say "  omarchy plugin disable $THIRD_PARTY_LOCK"
  say "  omarchy plugin enable  $PLUGIN_ID"
elif [[ -d $HOME/.config/omarchy/plugins/$THIRD_PARTY_LOCK ]]; then
  say "== retire the third-party lock plugin (Split now ships here)"
  run omarchy plugin disable "$THIRD_PARTY_LOCK"
fi

say
say "Done. The plugin directory is watched, but a plugin of kind \"service\" is"
say "loaded once (keepLoaded): the lock that is live now stays live, so enabling"
say "this one silently loses the handler race. Restart the shell to finish:"
say "  omarchy-restart-shell"
say
say "Then test it yourself: lock the session, unlock with your password, and"
say "press Enter on an empty field for face unlock. Rollback is in the header."
say
say "If it ever locks with a black screen, that is recoverable: switch VT"
say "(Ctrl+Alt+F2..F6), log in, and run: systemctl --user restart omarchy-shell"
