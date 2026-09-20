#!/bin/bash
# Install Split Lock as an Omarchy shell plugin.
#
# The lock is a "service" plugin, and the shell instantiates `LockView { }` by
# **filename** out of the plugin's own directory. So the swap is: ship
# omarchy's lock service plus our LockView.qml and the Split design files flat
# next to it. Nothing in omarchy's tree is touched, and no third-party lock
# plugin is needed. Service.qml is that same service with our own face/avatar
# blocks in it (marked `PORT (split-lock)`), not a verbatim copy.
#
# Face unlock needs one root-side file as well -- /etc/pam.d/omarchy-lock-face,
# written by face-pam.sh. Without it the plugin still installs and simply keeps
# the face affordance hidden.
#
#   ./install.sh              install, then disable the third-party lock plugin
#   ./install.sh --stage      install but leave it disabled, so the lock in use
#                             does not change until you say so
#   ./install.sh --dry-run    say what it would do, change nothing
#
# Rollback (the whole thing is one directory):
#   rm -rf ~/.config/omarchy/plugins/jianlongliu.split-lock
#   omarchy plugin enable io.github.sirjul1337.lock-explorer
#   omarchy-restart-shell
# and, only if you want face auth gone too: sudo ./face-pam.sh --remove
#
# If the session ever locks with nothing on screen, the way out is a text
# console: switch VT, log in, `systemctl --user restart omarchy-shell`. Killing
# the ext-session-lock client is what releases the lock, so that always works
# even when nothing else does.
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PLUGIN_ID=jianlongliu.split-lock
THIRD_PARTY_LOCK=io.github.sirjul1337.lock-explorer
DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
OMARCHY=${OMARCHY_PATH:-"$HOME/.local/share/omarchy"}
SOURCE_SERVICE="$OMARCHY/shell/plugins/lock/Service.qml"
LOCK_PAM=/etc/pam.d/omarchy-lock-password
FACE_PAM=/etc/pam.d/omarchy-lock-face

# Service.qml is upstream's lock service plus this port's own delta: the face
# probe/PAM flow and the avatar probe (every block is marked `PORT (split-lock)`).
# UPSTREAM_SERVICE_MD5 is the drift detector -- if upstream's file no longer
# hashes to it, our delta was written against an older service and wants a
# re-read of both. EXPECTED_SERVICE_MD5 is our own file, so an accidental edit
# to the installed copy gets caught too.
UPSTREAM_SERVICE_MD5=a2f85612e11c7e2c39cdab0a43e8d9a0
EXPECTED_SERVICE_MD5=fbf03b5a5d1ea4c23447d50de62ff0f9

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

if [[ -f $FACE_PAM ]]; then
  say "  face pam service present: $FACE_PAM"
else
  say "  NOTE: no $FACE_PAM, so the lock just hides its face affordance."
  say "        Run: sudo $HERE/face-pam.sh"
fi

if [[ -f $SOURCE_SERVICE ]]; then
  actual=$(md5sum "$SOURCE_SERVICE" | cut -d' ' -f1)
  if [[ $actual == "$UPSTREAM_SERVICE_MD5" ]]; then
    say "  our delta is against current upstream ($UPSTREAM_SERVICE_MD5)"
  else
    say "  WARNING: upstream Service.qml changed (delta built against"
    say "           $UPSTREAM_SERVICE_MD5, upstream $actual). Re-read our"
    say "           PORT (split-lock) blocks onto the new file:"
    say "           diff '$SOURCE_SERVICE' '$HERE/Service.qml'"
  fi
else
  say "  WARNING: no upstream lock service at $SOURCE_SERVICE, is omarchy installed?"
fi

ours=$(md5sum "$HERE/Service.qml" | cut -d' ' -f1)
if [[ $ours == "$EXPECTED_SERVICE_MD5" ]]; then
  say "  our Service.qml is the reviewed one ($EXPECTED_SERVICE_MD5)"
else
  say "  WARNING: our Service.qml is not the reviewed one (expected"
  say "           $EXPECTED_SERVICE_MD5, got $ours). Re-run the contract test"
  say "           and update the hash once the change is reviewed:"
  say "           (cd '$HERE' && ./tests/state.sh)"
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
say "Then test it yourself: lock the session and unlock with your password,"
say "with the fingerprint line, and with Enter on an empty field (face)."
say "The avatar comes from the account picture; lock preview shows both without"
say "locking anything: omarchy-shell lock preview"
say
say "If it ever locks with a black screen, that is recoverable: switch VT"
say "(Ctrl+Alt+F2..F6), log in, and run: systemctl --user restart omarchy-shell"
