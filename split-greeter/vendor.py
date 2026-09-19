#!/usr/bin/env python3
"""Re-vendor the lock-screen components this greeter renders, then re-apply the
greeter patches.

The Split design and the two Omarchy shell modules it sits on (qs.Commons,
qs.Ui) are copied rather than imported so the greeter carries no dependency on
a running Omarchy shell — the greeter user cannot read the user's home, and the
shell is not running during login.

Sources:
  designs/       <- ~/.config/omarchy/plugins/io.github.sirjul1337.lock-explorer
  Commons/, Ui/  <- ~/.local/share/omarchy/shell

Run after updating either source (the plugin's releases, `omarchy update`).
Patch list at the bottom: the only places the greeter changes vendored code.
"""

import os
import re
import shutil
import sys

HOME = os.path.expanduser("~")
PLUGIN = os.path.join(HOME, ".config/omarchy/plugins/io.github.sirjul1337.lock-explorer")
SHELL = os.environ.get("OMARCHY_SHELL", os.path.join(HOME, ".local/share/omarchy/shell"))
HERE = os.path.dirname(os.path.abspath(__file__))

# Type names that come from Qt or Quickshell, i.e. never vendored.
BUILTIN = {
    "Behavior", "BorderImage", "Column", "Connections", "Item", "Image", "Loader",
    "MouseArea", "MultiEffect", "NumberAnimation", "Rectangle", "Row", "SequentialAnimation",
    "ShaderEffect", "Text", "TextEdit", "TextInput", "TextMetrics", "Timer", "Translate",
    "OpacityAnimator", "Scale", "ScrollView", "ListView", "ColumnLayout", "RowLayout",
}

SEEDS = [
    ("designs", PLUGIN + "/designs", "Split.qml"),
    ("Commons", SHELL + "/Commons", "Color.qml"),
    ("Ui", SHELL + "/Ui", "BorderSurface.qml"),
]

# path -> [(original, patched), ...]: the first entry whose original is found
# wins, and a file is left alone when any patched form is already present.
HINT_PATCH = '''          // greeter patch: login, not unlock; and the host can take the line
          // over (face scan running, PAM talking).
          : (lock.hintOverride.length > 0 ? lock.hintOverride
            : (lock.fingerprintConfigured ? "\U000f01a0  Touch the sensor or press Enter" : "Press Enter to log in"))'''

# The face hint is a whole sentence ("...or just type your password") and the
# panel is only ~323px wide inside its margins, so the line has to wrap -- the
# panel clips, and the tail was simply cut off.
HINT_WRAP_OLD = '''      Text {
        opacity: lock.snapshotMode ? 0 : 1
        text: lock.failedAttempts > 0'''

HINT_WRAP_NEW = '''      Text {
        opacity: lock.snapshotMode ? 0 : 1
        // greeter patch: the face hint is a whole sentence ("...or just type
        // your password") and the panel is only ~323px wide inside its margins,
        // so without this its tail is clipped by the panel.
        objectName: "lockHint"
        width: lock.fieldWidth
        wrapMode: Text.WordWrap
        text: lock.failedAttempts > 0'''

# The design's own avatar becomes the account switcher; the host opts in with
# avatarClickable = true (shell.qml does), so a design instance that is only
# scenery -- the lock screen -- keeps a plain picture.
AVATAR_OLD = '''      Avatar {
        lock: lock
        width: 84
        fontSize: Math.round(Style.font.baseSize * 3)
        borderWidth: 3
        borderColor: lock.withAlpha(Color.lock.text, 0.25)
        shadow: false
      }'''

AVATAR_NEW = '''      Avatar {
        id: avatarBadge
        lock: lock
        width: 84
        fontSize: Math.round(Style.font.baseSize * 3)
        borderWidth: 3
        // greeter patch: the avatar is the account switcher now. The ring
        // brightens on hover so it reads as a control, not a picture.
        borderColor: lock.avatarClickable && avatarHover.hovered
          ? lock.withAlpha(Color.lock.borderActive, 0.9)
          : lock.withAlpha(Color.lock.text, 0.25)
        shadow: false

        HoverHandler {
          id: avatarHover
          enabled: lock.avatarClickable
        }

        MouseArea {
          anchors.fill: parent
          enabled: lock.avatarClickable
          cursorShape: Qt.PointingHandCursor
          onClicked: lock.avatarClicked()
        }
      }'''

PATCHES = [
    ("designs/PasswordField.qml", [
        (
            '''    anchors.leftMargin: field.borderLeft + field.sidePadding + Math.max(field.fingerprintReserve, field.glyphReserve)''',
            '''    // greeter patch: the left inset only has to clear the lock glyph. Upstream
    // used max() of both reserves, which borrowed the right-hand icons' width
    // (eye + face) for the left side and pushed the text ~65px right of the
    // box's own padding.
    anchors.leftMargin: field.borderLeft + field.sidePadding + field.glyphReserve''',
        ),
    ]),
    ("designs/DesignBase.qml", [
        (
            '  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || "user"',
            '''  // greeter patch: on the lock screen the account is whoever is at the
  // keyboard; on the greeter it is the account being logged into, which is not
  // the `greeter` user running this process.
  property string loginUser: ""
  readonly property string userName: loginUser.length > 0
    ? loginUser
    : (Quickshell.env("USER") || Quickshell.env("LOGNAME") || "user")''',
        ),
        (
            "  property Item inputItem: null",
            '''  // greeter patch: host-supplied replacement for the design's own hint line
  // (e.g. "look at the camera" while a face scan runs).
  property string hintOverride: ""

  property Item inputItem: null''',
        ),
        (
            '''  // greeter patch: host-supplied replacement for the design's own hint line
  // (e.g. "look at the camera" while a face scan runs).
  property string hintOverride: ""''',
            '''  // greeter patch: host hook that turns the panel's avatar into a control. The
  // account picker hangs off it now; the corner chip that used to do the job
  // was easy to miss, and the avatar is already the thing that says who you are.
  property bool avatarClickable: false
  signal avatarClicked()

  // greeter patch: host-supplied replacement for the design's own hint line
  // (e.g. "look at the camera" while a face scan runs).
  property string hintOverride: ""''',
        ),
    ]),
    ("designs/Split.qml", [
        (
            '          : (lock.fingerprintConfigured ? "\U000f01a0  Touch the sensor or press Enter" : "Press Enter to unlock")',
            HINT_PATCH,
        ),
        (
            '          : (lock.fingerprintConfigured ? "\U000f01a0  Touch the sensor or press Enter" : "Press Enter to log in")',
            HINT_PATCH,
        ),
        (HINT_WRAP_OLD, HINT_WRAP_NEW),
        (AVATAR_OLD, AVATAR_NEW),
    ]),
    ("Commons/Color.qml", [
        (
            '  readonly property string currentThemePath: stateHome + "/omarchy/current/theme"',
            '''  // greeter patch: with several accounts on the login screen the palette
  // has to follow the selected account, not the greeter user's HOME. The host
  // sets themeOverride to that account's synced theme directory.
  property string themeOverride: ""
  readonly property string currentThemePath: themeOverride.length > 0
    ? themeOverride
    : stateHome + "/omarchy/current/theme"''',
        ),
    ]),
    ("Commons/Style.qml", [
        (
            "  property int cornerRadius: 0",
            '''  // greeter patch: the greeter runs outside the Omarchy shell, where the
  // hyprctl probe below cannot answer. Take the radius from the environment
  // instead (niri.kdl sets GREETER_CORNER_RADIUS).
  property int cornerRadius: Number(Quickshell.env("GREETER_CORNER_RADIUS")) || 0''',
        ),
    ]),
]


def components(text):
    """Capitalised identifiers instantiated in this file."""
    return set(re.findall(r"\b([A-Z][A-Za-z0-9]+)\s*\{", text))


def vendor():
    copied = []
    for target, source, seed in SEEDS:
        dest_dir = os.path.join(HERE, target)
        os.makedirs(dest_dir, exist_ok=True)
        queue = [seed]
        while queue:
            name = queue.pop(0)
            src = os.path.join(source, name)
            dst = os.path.join(dest_dir, name)
            text = open(src).read()
            if not os.path.exists(dst) or os.path.getmtime(dst) < os.path.getmtime(src):
                shutil.copy(src, dst)
                copied.append(os.path.join(target, name))
            for name2 in components(text):
                if name2 in BUILTIN or not os.path.exists(os.path.join(source, name2 + ".qml")):
                    continue
                queue.append(name2 + ".qml")
    return copied


def write_qmldirs():
    for target, source, _ in SEEDS:
        if target == "designs":  # imported as a plain relative directory
            continue
        dest_dir = os.path.join(HERE, target)
        entries = sorted(f for f in os.listdir(dest_dir) if f.endswith(".qml"))
        with open(os.path.join(dest_dir, "qmldir"), "w") as handle:
            handle.write("module qs.%s\n" % target)
            for entry in entries:
                # Color/Style/Util/Border/Niri are `pragma Singleton`; dropping
                # the keyword silently turns every `Color.lock` into a
                # "cannot read property of undefined".
                keyword = "singleton " if "pragma Singleton" in open(os.path.join(dest_dir, entry)).read() else ""
                handle.write("%s%s 1.0 %s\n" % (keyword, entry[:-4], entry))


def apply_patches():
    status = 0
    for relative, alternatives in PATCHES:
        path = os.path.join(HERE, relative)
        text = open(path).read()
        for old, new in alternatives:
            if new in text:      # this one is already in place
                continue
            if text.count(old) == 1:
                text = text.replace(old, new)
                open(path, "w").write(text)
                print("patched: %s" % relative)
        if not all(new in text for old, new in alternatives):
            print("FAILED to patch %s" % relative, file=sys.stderr)
            status = 1
    return status


if __name__ == "__main__":
    for changed in vendor():
        print("vendored: %s" % changed)
    write_qmldirs()
    sys.exit(apply_patches())
