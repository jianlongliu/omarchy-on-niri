# Split Greeter and Split Lock — third-party code

The login screen in `split-greeter/` is called **Split Greeter**: it is a greetd
greeter (a Quickshell front end) built around the **Split** design from
`io.github.sirjul1337.lock-explorer` by SirJul1337 — hence the name. The design
is used under the MIT license below, with attribution; it is not our work.

`split-lock/` is the same design used as the session lock instead of a login
screen, and vendors the same files. Its `Service.qml` is a verbatim copy of
Omarchy's built-in `omarchy.lock` service (covered by [LICENSE](LICENSE)); it
ships unchanged because the lock service instantiates `LockView { }` by filename
out of its own directory — which is exactly what makes `LockView.qml` here the
entire adapter. `reference/` holds read-only copies of the upstream service and
view for comparison, under the same terms.


This repository is a port of [Omarchy](https://github.com/basecamp/omarchy) for
niri. Omarchy's MIT license and copyright (David Heinemeier Hansson) are in
[LICENSE](LICENSE) and cover everything not listed below.

## omarchy-lock-explorer — MIT, Copyright (c) 2026 SirJul1337

`split-greeter/designs/`, `split-greeter/Commons/`, `split-greeter/Ui/` and the
design files in `split-lock/` (`Split.qml`, `DesignBase.qml`, `LockInput.qml`,
`PasswordField.qml`, `Avatar.qml`, `Wallpaper.qml`) are vendored from the
`io.github.sirjul1337.lock-explorer` plugin, which both reuse (the Split design).
Its license, verbatim:

```
MIT License

Copyright (c) 2026 SirJul1337

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

That plugin's own `Service.qml` is based on Omarchy's built-in `omarchy.lock`
plugin, which is covered by [LICENSE](LICENSE).

The Split Greeter's own code (`shell.qml`, `Greetd.qml`, `UserPicker.qml`, `Users.qml`,
`SelfTest.qml`, `StateTest.qml`, `bridge/`, `tests/`, `install.sh`, `sync.sh`,
`niri.kdl`) was written for this port and is covered by [LICENSE](LICENSE).

So was the Split Lock's (`LockView.qml`, `manifest.json`, `install.sh`,
`vendor.py`, `tests/`).
