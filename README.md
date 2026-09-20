# Omarchy on niri

> **简体中文 → [README.zh.md](README.zh.md)**

Port of [basecamp/omarchy](https://github.com/basecamp/omarchy) (`quattro` / `4.0.0.alpha`) to the
[niri](https://github.com/YaLTeR/niri) Wayland compositor, instead of Hyprland.

This repo contains the ported Omarchy source plus the glue that makes it run on niri. It is **not a
standalone installer** — it assumes a working Arch + niri login session and an existing Omarchy install
(or that you install Omarchy first). What it gives you is:

- The Omarchy source with the QML/Niri port applied (`shell/Commons/Niri.qml`, patched
  `Bar.qml` / `Workspaces.qml` / `Background.qml`).
- `port-bin/` — the PATH-first override scripts that translate the Hyprland-coupled bits to niri
  (the `hyprctl` shim is the critical one; `uwsm-app` rescues every `uwsm-app -- <cmd>` call site
  in Omarchy's `bin/`, which is a uwsm-session facility a niri session does not have; `omarchy-update`
  replaces the upstream updater, which assumes the Omarchy package repo is configured; plus the
  picker warm-up and the display text-size shim).
- `niri-port/` — the idempotent overlay patch (`niri.patch` + `Niri.qml`) that survives `omarchy update`,
  plus `plugin-patches/` (local edits to third-party bar plugins, applied by hand — nothing replays them).
- `niri-config/local/` — the niri config this machine actually runs (seven `*.kdl` files: `config` plus
  `input/monitor/layout/window-rules/effects/binds`; the home directory is a `/home/<user>` placeholder —
  see the README in that directory).
- `niri-config/omarchy.kdl.template` + `shell.json` — the other route: one merged file rendered by
  `install.sh` (this machine never used it).
- `hooks/` — Omarchy update/theme hooks that reapply the port.
- `default/systemd/user/omarchy-picker-warmup.service` — the session-scoped picker warm-up unit
  (`install.sh` installs and enables it; disable with `toggles/picker-warmup-off`).
- `install.sh` — optional convenience wrapper. **Not the supported path**: the manual steps are in
  `docs/INSTALL.md` and should be followed by hand.
- `docs/INSTALL.md` — the hand-run install procedure (deps, file placement, config merge, overlay, backlight).
- `docs/omarchy-on-niri-port.md` — the main volume (current facts: constraints, architecture, file
  inventory, niri config, deployment, verification, environment) plus the module map.
- `docs/visual.md` — visual adjustments volume (frosted blur stack, text size/DPI, focus ring
  gradient, menu backdrop, gaps, overview, theming, wallpaper library, scaling).
- `docs/behavior.md` — behavior volume (keys and dedup, system actions, power/backlight,
  screensaver, input sources, menu behavior, picker performance and warm-up, battery work).
- `docs/plugins.md` — the plugin volume (bar plugin layer, per-plugin local patches and ops).
- `docs/shims.md` — the shim volume (`hyprctl`, `uwsm-app`, `omarchy-update`, `display-text-size`,
  `picker-warmup`, … the PATH-first overrides).
- `docs/upstream.md` — keeping up with upstream (overlay replay, merge baselines, release flow).
- `docs/migration.md` — the account migration volume (experiment account → main account, 2026-09-19).
- `docs/local-overrides.md` — what this machine has beyond the repo, and how to roll it back.
- `docs/lock.md` — the lock screen and login volume: the Split Greeter, `split-lock`, the PAM gate,
  howdy and avatars, and greetd's single `configuring` slot.

The volumes keep the original section numbering (`§8 第 N 条`, `§8.x`, `§11.x`); the main volume
holds a map from every moved section to its volume. The volumes have exactly one home — `docs/`
itself; the `~/Documents/omarchy-niri-*.md` names are symlinks into it, and `scripts/check-doc-links.sh`
makes sure nobody turns one back into a drifting copy.

## Repository layout

```
omarchy-on-niri/
├── shell/        <- ported Omarchy Quickshell source (Layer 1)
├── bin/          <- Omarchy's own scripts (unchanged upstream)
├── port-bin/     <- port glue: hyprctl shim + niri system/power/theme/repatch scripts
│                     install.sh copies these into ~/bin (PATH-first, survives `omarchy update`)
├── niri-port/    <- overlay: niri.patch + Niri.qml (reapplied after each update)
├── niri-config/  <- local/*.kdl (what this machine runs) + omarchy.kdl.template (the other route)
│                     + shell.json sample (Omarchy config layer 1)
├── hooks/        <- post-update.d/10-niri-repatch, theme-set.d/10-niri-border
├── install.sh    <- optional convenience wrapper (prefer the manual steps in docs/INSTALL.md)
├── docs/INSTALL.md  <- hand-run install procedure
├── docs/omarchy-on-niri-port.md <- main volume: current facts + module map
├── docs/{visual,behavior,plugins,shims,upstream,migration,lock,local-overrides}.md <- module volumes
├── scripts/     <- check-doc-links.sh (the nine ~/Documents convenience names still point into docs/)
└── README.md
```

## Requirements / dependencies

Install these on the target Arch machine. Everything below was verified in use on the porting machine
(March 2026 / Arch rolling, systemd 261, niri 26.04); verify package availability on your box.

### Required — the shell engine
| Package | Why |
|---|---|
| `niri` | The compositor itself. This port targets niri (26.x). |
| `quickshell` | The layer-shell QML engine that renders the Omarchy bar/menus/OSD. Omarchy's shell is Quickshell-based. Install via repo/AUR as appropriate. |
| `git`, `base-devel` | To clone/build/install Omarchy (and this port). |

### Required — Omarchy runtime helpers
| Package | Why |
|---|---|
| `jq` | Used by many `omarchy-*` scripts and the `hyprctl` shim to parse JSON. |
| `qt6-imageformats` | **Critical.** Lets Qt Quick decode the `.webp` Omarchy wallpapers. Without it you get a black wallpaper. |
| `inotify-tools` | Provides `inotifywait`, used by the Omarchy plugin watcher (`~/.config/omarchy/plugins`). |
| `wl-clipboard` | Provides `wl-copy` / `wl-paste`, used by the clipboard manager plugin. |
| `brightnessctl` | Backlight control for the brightness media keys / OSD. |

### Required — audio/media
| Package | Why |
|---|---|
| `pipewire` + `wireplumber` (and `pipewire-pulse`) | Audio backend; `wpctl` drives the volume OSD. |
| `playerctl` | Media transport keys (play/pause/next/prev). |
| `ghostty` | The default terminal (`Mod+Return` / `Mod+T`). |

### Power backend (one of these)
| Package | Why |
|---|---|
| `power-profiles-daemon` | Provides `powerprofilesctl`. `port-bin/omarchy-powerprofiles-*` prefers this. |
| **or** `tlp` + `tlp-pd` | The porting machine uses TLP (`powerprofilesctl` absent). The shim falls back to TLP's `net.hadess.PowerProfiles` D-Bus interface. |

### Optional
| Package | Why |
|---|---|
| `satty` | Screenshot annotation. |
| `swappy` | Alternate screenshot editor. |
| `grim` / `slurp` | Niri screenshots / region capture (niri provides its own, but some capture helpers call these). |

### Non-package prerequisites
- A **backlight device** under `/sys/class/backlight/` (e.g. `intel_backlight`). `brightnessctl` needs the
  `video` group / a matching udev rule to write without root:
  - `/etc/udev/rules.d/90-backlight.rules`: `SUBSYSTEM=="backlight" GROUP="video" MODE="0664"`
  - `usermod -aG video <user>`
- A **logind session** with polkit `org.freedesktop.login1.reboot` / `power-off` set to `allow_active=yes`
  (systemd defaults to this on Arch) so the system switch works passwordless.

## Install

The manual, hand-run procedure is in **`docs/INSTALL.md`** (deps, `~/bin` glue, config.kdl merge, overlay,
backlight, per-machine checks). It is the supported path.

There is also an optional `install.sh` bootstrap that lays down the same files, but it does **not** rewrite
an existing `config.kdl` and it will not auto-install packages or fix backlight perms — follow
`docs/INSTALL.md` to be sure.

Short version:

```sh
git clone https://github.com/jianlongliu/omarchy-on-niri
cd omarchy-on-niri
# install the packages in README "Requirements", then run:
./install.sh            # optional; or follow docs/INSTALL.md step by step
```

Then log out and back in — `spawn-sh-at-startup` starts the Quickshell shell.

## Per-machine adjustments (must check)

These are hardware/OS specific and **cannot be auto-detected reliably**:

1. **Monitor output name** — port uses `eDP-1` in a few places; run `niri msg outputs` and adjust.
2. **Backlight device** — `intel_backlight` on the porting box; check `/sys/class/backlight/*`.
3. **Power backend** — TLP vs power-profiles-daemon changes what `omarchy-powerprofiles-*` reports.
4. **niri version** — tested on 26.04; keybind/overview behavior may differ across releases.
5. **Lock screen auth** — `/etc/pam.d/omarchy-lock-password` comes from the Omarchy installer, which this
   manual path skips. Without it the lock screen refuses to lock at all (`omarchy-shell lock status` →
   `"passwordPam":false`); run `pkexec ~/.local/share/omarchy/bin/omarchy-apply-lock` once (INSTALL step 8).

The overview backdrop needs no adjustment: niri draws that layer itself, so the ported `blurwallpaper` shell plugin paints a blurred wallpaper while the overview is open (see the port notes).

## Why it's not a single-click guarantee

The port reuses Omarchy's own install but swaps Hyprland for niri via the `hyprctl` shim and a
`Niri.qml` Quickshell model. Because Omarchy scripts call `hyprctl` ~50 times, the shim must be on
`PATH` for the shell to function. Files in `~/.local/share/omarchy` are patched in the working tree and
kept **uncommitted** so the `niri.patch` overlay can be reapplied after each `omarchy update` — do not
commit inside `~/.local/share/omarchy` or the fast-forward update will break.

See `docs/omarchy-on-niri-port.md` for the full decision log.
