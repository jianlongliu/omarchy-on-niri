# Manual install (no script)

> **简体中文 → [INSTALL.zh.md](INSTALL.zh.md)**

Follow these steps by hand on the target machine. This is the supported path — `install.sh` is just a
convenience wrapper; everything below is what it actually does, spelled out so you can do it yourself.

Assumptions: you are on **Arch + niri**, logged in as your user, and **Omarchy is already installed** at
`~/.local/share/omarchy` (it has its own installer). You have this repo cloned somewhere; set `REPO`
below to that path.

```sh
REPO=/path/to/omarchy-on-niri     # <-- change me
```

---

## 1. System packages

```sh
sudo pacman -S --needed \
  git base-devel jq qt6-imageformats inotify-tools wl-clipboard \
  pipewire wireplumber playerctl ghostty
```

- **quickshell** (the QML engine the Omarchy shell runs on) — in the Arch repos on newer versions, else
  via AUR (`quickshell-git`). Install it or the shell won't render.
- **Power backend — pick one:**
  - `sudo pacman -S --needed power-profiles-daemon` (provides `powerprofilesctl`), **or**
  - `sudo pacman -S --needed tlp tlp-pd` (the porting machine uses this; `powerprofilesctl` is absent and
    `port-bin/omarchy-powerprofiles-*` falls back to TLP's D-Bus interface).
- **Optional:** `satty` (screenshot annotate), `swappy`, `grim slurp` (capture helpers).

`qt6-imageformats` is critical: without it Qt can't decode the `.webp` wallpapers and you get a black
background.

---

## 2. Put the port glue in `~/bin`

These are PATH-first overrides that translate the Hyprland-coupled pieces to niri. `~/bin` must come
**first** in `PATH` — that's set in the niri config env block (step 3).

```sh
mkdir -p ~/bin
for f in "$REPO"/port-bin/*; do install -m 0755 "$f" ~/bin/; done
```

This installs: `hyprctl` (the shim — **critical**, ~50 omarchy scripts call it), `omarchy-niri-system`,
`omarchy-niri-apply-theme`, `omarchy-niri-repatch`, `omarchy-powerprofiles-list`, `omarchy-powerprofiles-set`.

---

## 3. Wire the compositor (`~/.config/niri/config.kdl`)

Back up first, then merge. Copy the relevant lines from generating the template by substituting your home
path in place of `__HOME__`:

```sh
mkdir -p ~/.config/niri
sed "s|__HOME__|$HOME|g" "$REPO/niri-config/omarchy.kdl.template" > ~/.config/niri/omarchy.kdl
cp ~/.config/niri/config.kdl ~/.config/niri/config.kdl.bak 2>/dev/null || true
```

Then edit `~/.config/niri/config.kdl`:

1. **Top level** — add the `environment { }` block and the `spawn-sh-at-startup` line:

   ```kdl
   environment {
       OMARCHY_PATH "/home/you/.local/share/omarchy"
       PATH "/home/you/bin:/home/you/.local/share/omarchy/bin:/home/you/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
   }

   spawn-sh-at-startup "quickshell -n -p /home/you/.local/share/omarchy/shell"
   ```

   (Use your real path, not `/home/you`.)

2. **Inside your existing `binds { }` block** — paste the Omarchy bindings. The full list is in
   `~/config/niri/omarchy.kdl` (generated above); the important ones:

   ```kdl
   Mod+Space         hotkey-overlay-title="Omarchy Menu" { spawn-sh "omarchy-menu toggle"; }
   Mod+K             hotkey-overlay-title="Keybindings"  { spawn-sh "omarchy-menu-keybindings"; }
   Mod+Ctrl+L        hotkey-overlay-title="Lock system"  { spawn-sh "omarchy-system-lock"; }
   Mod+Ctrl+P        hotkey-overlay-title="Power"        { spawn-sh "omarchy-shell shell toggle omarchy.power"; }
   Mod+Return        hotkey-overlay-title="Terminal"     { spawn "ghostty"; }
   XF86AudioRaiseVolume allow-when-locked=true hotkey-overlay-title="Volume up" { spawn-sh "omarchy-audio-output-volume raise"; }
   XF86MonBrightnessUp   allow-when-locked=true hotkey-overlay-title="Brightness up" { spawn-sh "omarchy-brightness-display +5%"; }
   ```

Validate:

```sh
niri validate -c ~/.config/niri/config.kdl
```

---

## 4. Omarchy config layer 1 (`~/.config/omarchy/shell.json`)

Only if it doesn't already exist (it holds your bar layout / idle timers):

```sh
mkdir -p ~/.config/omarchy
cp "$REPO/niri-config/shell.json" ~/.config/omarchy/shell.json
```

---

## 5. Update / theme hooks

```sh
mkdir -p ~/.config/omarchy/hooks/post-update.d ~/.config/omarchy/hooks/theme-set.d
install -m 0755 "$REPO"/hooks/post-update.d/* ~/.config/omarchy/hooks/post-update.d/
install -m 0755 "$REPO"/hooks/theme-set.d/*    ~/.config/omarchy/hooks/theme-set.d/
```

`post-update.d/10-niri-repatch` reapplies the overlay after each `omarchy update`;
`theme-set.d/10-niri-border` writes the focus-ring color on each style switch.

---

## 6. Apply the port overlay to the Omarchy install

Put the overlay where repatch expects it, then apply (idempotent):

```sh
mkdir -p ~/.config/omarchy/niri-port
cp "$REPO"/niri-port/niri.patch "$REPO"/niri-port/Niri.qml ~/.config/omarchy/niri-port/

cd ~/.local/share/omarchy
cp ~/.config/omarchy/niri-port/Niri.qml shell/Commons/Niri.qml
git apply --reverse --check ~/.config/omarchy/niri-port/niri.patch 2>/dev/null \
  && echo "overlay already applied" \
  || git apply ~/.config/omarchy/niri-port/niri.patch
```

**Important:** keep the file changes in `~/.local/share/omarchy` **uncommitted**. The `niri.patch` overlay is
re-applied after each `omarchy update`; committing inside that repo would break the update's fast-forward.
Run `~/bin/omarchy-niri-repatch` after any update to restore the port.

---

## 7. Backlight permissions (udev + video group)

So `brightnessctl` can write without root:

```sh
echo 'SUBSYSTEM=="backlight" GROUP="video" MODE="0664"' | sudo tee /etc/udev/rules.d/90-backlight.rules
sudo usermod -aG video "$USER"
sudo udevadm control --reload-rules && sudo udevadm trigger

# udev trigger only sends 'change' and won't reapply group/mode to the existing node,
# so backstop it now (applied properly at next boot):
node=$(echo /sys/class/backlight/*/brightness); sudo chgrp video "$node"; sudo chmod 0664 "$node"
```

---

## 8. Per-machine checks (must verify by hand)

These can't be auto-detected and will differ per box:

1. **Monitor output name** — the port/node config references `eDP-1` in places; run `niri msg outputs` and
   adjust to your output name.
2. **Backlight device** — `intel_backlight` on the porting box; confirm yours under `/sys/class/backlight/*`.
3. **Power backend** — power-profiles-daemon (`powerprofilesctl`) vs TLP (`tlp + tlp-pd`); this changes what
   `omarchy-powerprofiles-*` reports and what the Power menu shows.
4. **niri version** — tested on 26.04; keybind/overview behavior can differ across releases.

---

## 9. Start and verify

Log out and back in — `spawn-sh-at-startup` starts the Quickshell shell. Then check:

```sh
niri msg layers                       # omarchy-background + omarchy-bar present?
niri msg action spawn -- omarchy-menu toggle   # menu opens?
~/bin/omarchy-niri-system <arg-bogus> # expect usage + exit 2
niri msg action spawn -- omarchy-system-logout   # (ends session; only when ready)
```

Bar should render workspaces/clock/keyboard layout; `Mod+Space` opens the menu; media keys show an OSD;
the Power menu shows log out / reboot / shutdown.

See `omarchy-on-niri-port.md` for the full port notes and `README.md` for the dependency rationale.
