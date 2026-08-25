#!/usr/bin/env bash
# omarchy-on-niri — bootstrap a fresh Arch + niri machine with the port glue.
#
# Non-destructive: only copies the port override scripts into ~/bin, writes the
# Omarchy config layer if absent, installs the update/theme hooks, and applies
# the idempotent overlay patch to the Omarchy install. It does NOT rewrite an
# existing niri config.kdl blindly — the compositor wiring is printed as a
# manual merge step (see niri-config/omarchy.kdl.template).
#
# Usage: ./install.sh
#   Omarchy must already be installed (its installer places it at ~/.local/share/omarchy).

set -euo pipefail

HOME_DIR="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY_PATH="${OMARCHY_PATH:-$HOME_DIR/.local/share/omarchy}"
BIN_DIR="$HOME_DIR/bin"
NIRI_CONF="$HOME_DIR/.config/niri/config.kdl"

log()  { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }

if [[ ! -d "$OMARCHY_PATH/shell" ]]; then
  warn "Omarchy install not found at $OMARCHY_PATH/shell."
  warn "Install Omarchy first (its installer creates ~/.local/share/omarchy), then re-run."
  exit 1
fi

# ---- 1. port-bin overrides -> ~/bin (PATH-first, survives `omarchy update`) ----
log "Installing port override scripts to $BIN_DIR"
mkdir -p "$BIN_DIR"
for f in "$REPO_DIR"/port-bin/*; do
  [[ -f "$f" ]] || continue
  install -m 0755 "$f" "$BIN_DIR/$(basename "$f")"
done

# ---- 2. Omarchy config layer 1 (only if absent) ----
log "Writing Omarchy config layer (~/.config/omarchy/shell.json) if absent"
mkdir -p "$HOME_DIR/.config/omarchy"
if [[ ! -f "$HOME_DIR/.config/omarchy/shell.json" ]]; then
  install -m 0600 "$REPO_DIR/niri-config/shell.json" "$HOME_DIR/.config/omarchy/shell.json"
else
  warn "~/.config/omarchy/shell.json exists; leaving it (it holds your theme/font config)."
fi

# ---- 3. omarchy update/theme hooks ----
log "Installing omarchy hooks (~/.config/omarchy/hooks)"
mkdir -p "$HOME_DIR/.config/omarchy/hooks/post-update.d" "$HOME_DIR/.config/omarchy/hooks/theme-set.d"
install -m 0755 "$REPO_DIR"/hooks/post-update.d/* "$HOME_DIR/.config/omarchy/hooks/post-update.d/"
install -m 0755 "$REPO_DIR"/hooks/theme-set.d/*    "$HOME_DIR/.config/omarchy/hooks/theme-set.d/"

# ---- 4. apply the idempotent overlay patch to the Omarchy install ----
if [[ -x "$BIN_DIR/omarchy-niri-repatch" ]]; then
  log "Applying niri-port overlay to $OMARCHY_PATH (idempotent)"
  "$BIN_DIR/omarchy-niri-repatch" || warn "repatch returned nonzero (see ~/bin/omarchy-niri-repatch)"
else
  warn "omarchy-niri-repatch not in ~/bin; skipping overlay apply (will be installed next run)."
fi

# ---- 5. niri compositor wiring: prepare snippet + print manual step ----
log "Preparing niri composeor snippet at ~/.config/niri/omarchy.kdl"
mkdir -p "$HOME_DIR/.config/niri"
sed "s|__HOME__|$HOME_DIR|g" "$REPO_DIR/niri-config/omarchy.kdl.template" > "$HOME_DIR/.config/niri/omarchy.kdl"

if [[ -f "$NIRI_CONF" ]]; then
  warn "Merge the generated ~/.config/niri/omarchy.kdl into your config.kdl:"
  warn "  1) paste its 'environment { }' and 'spawn-sh-at-startup' lines at TOP LEVEL, and"
  warn "  2) paste its 'binds { ... }' body inside the existing 'binds { }' block."
  warn "Then run: niri validate -c ~/.config/niri/config.kdl"
else
  warn "No existing niri config.kdl; install the generated ~/.config/niri/omarchy.kdl as a starting point."
fi

# ---- 6. per-machine reminders ----
warn ""
warn "Per-machine checks (cannot be auto-detected reliably):"
warn "  - monitor output name: run 'niri msg outputs' and adjust any hardcoded eDP-1."
warn "  - backlight device:    check /sys/class/backlight/* (e.g. intel_backlight) + udev/video group rules."
warn "  - power backend:       power-profiles-daemon (powerprofilesctl) or TLP (tlp + tlp-pd)."
warn "  - system deps:         see README.md 'Requirements / dependencies' (jq, qt6-imageformats, inotify-tools, etc.)."
warn ""

log "Done. Log out and back in; spawn-sh-at-startup starts the Omarchy shell."
