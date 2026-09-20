# Plugin patches

Local edits to third-party Omarchy bar plugins, as `git diff` output against each plugin's own
upstream checkout. `~/.config/omarchy/plugins/<id>/` **is** a git clone of the plugin, so a patch
here is generated in place:

```sh
cd ~/.config/omarchy/plugins/<id>
git diff > ~/.config/omarchy/niri-port/plugin-patches/<id>.patch
git apply --reverse --check ~/.config/omarchy/niri-port/plugin-patches/<id>.patch   # must pass
```

| Patch | What it changes |
|---|---|
| `charlieras262.floating-bar.patch` | Rounded `blurRegion` on the floating bar (the bar is a separate plugin here, not `omarchy.bar`) |
| `ronald.input-sources.patch` | `badgeOverrides` (Model.js) + `startupSource`/`applyStartupSource` (Panel.qml) so the first input source after a shell start is rime |
| `meviusisback.ai-subs.patch` | Font size from `caption` to `font.body` (five places), plus a leading pad and spacing so the chip lines up with the built-in widgets |
| `jianlongliu.workspaces.patch` | Dynamic workspace pill count (`1..N` by occupancy, never below 2) |

**Nothing replays these automatically.** `omarchy-niri-repatch` only covers `$OVL/niri.patch`,
`$OVL/Niri.qml` and whole-plugin copies under `$OVL/plugins/`; a plugin overwritten by
`omarchy plugin update` has to be patched by hand:

```sh
cd ~/.config/omarchy/plugins/<id>
git apply ~/omarchy-on-niri/niri-port/plugin-patches/<id>.patch
```

`jianlongliu.arch-logo`, `jianlongliu.workspaces` and `jianlongliu.split-lock` are ours, have no `.git`, and
`omarchy plugin update` does not touch them; their patches are made with
`diff -u --label a/<file> --label b/<file>` instead.

The `.bak-*` files that sit next to the live patches in `~/.config/omarchy/niri-port/plugin-patches/`
are machine-local history and are deliberately not tracked here.
