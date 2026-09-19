import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "designs"

// Omarchy greeter: the lock screen's Split design, standing in for a display
// manager. greetd runs us as `greeter` on a VT with its own niri instance; the
// Split instance below is the lock host, wired to Greetd (bridge to greetd).
ShellRoot {
  PanelWindow {
    id: window

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "split-greeter"
    // Overlay, like the lock screen: it is the only surface in the session, and
    // Exclusive keyboard focus is what niri grants on an overlay layer.
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive interactivity is granted when a surface maps; this one maps
    // while the greeter's niri is still coming up, so the grant can be missed
    // entirely (the login screen then looks fine and ignores the keyboard).
    // Mapping with it off and switching it on a moment later makes the
    // compositor see a change, the same trick the Omarchy shell's KeyboardPanel
    // uses. Cheap and harmless when the first grant did land.
    property bool focusPrimed: false
    WlrLayershell.keyboardFocus: window.focusPrimed
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    Timer {
      interval: 300
      running: true
      onTriggered: window.focusPrimed = true
    }
    exclusionMode: ExclusionMode.Ignore

    readonly property string stateDir: (Quickshell.env("HOME") || "/var/lib/greeter") + "/.local/state/split-greeter"
    // Per-account artwork, written by split-greeter-sync: the login screen
    // looks like the account it is about to log in (wallpaper + palette), so a
    // switch in the picker changes both. Startup shows the last logged-in
    // account. /var/lib/greeter/{theme,wallpaper} stays as the shared fallback.
    readonly property string accountsRoot: Quickshell.env("GREETER_ACCOUNTS_DIR") || "/var/lib/greeter/users"

    function accountTheme(user) {
      return window.accountsRoot + "/" + user + "/theme"
    }

    function accountWallpaper(user) {
      return window.accountsRoot + "/" + user + "/wallpaper"
    }

    Users { id: accounts }

    FileView {
      id: lastUser
      property string remembered: ""
      path: window.stateDir + "/last-user"
      printErrors: false
      watchChanges: false
      onLoaded: remembered = String(text() || "").trim()
      onTextChanged: remembered = String(text() || "").trim()
    }

    // The design is a lock screen: its LockInput takes item focus when the
    // design is created, and its only guard re-focuses after focus was *lost*
    // (nothing recovers a field that never got it). When the surface maps before
    // the compositor has made the window active, the field ends up permanently
    // unfocused — the window still gets keys (a window-level Shortcut fires) but
    // no keystroke ever reaches the password box, which is exactly what "typing
    // my password does nothing" was.
    //
    // So watch item focus instead of waiting for events: whoever holds the
    // keyboard when nothing is focused, give the field another chance. Skipped
    // while the account picker is open, since it takes focus on purpose.
    Timer {
      interval: 700
      running: true
      repeat: true
      onTriggered: {
        if (picker.open || greetd.sessionStarting) return
        var item = design.inputItem
        if (item && !item.activeFocus) {
          console.warn("greeter: the password field had no item focus, taking it back")
          design.forcePasswordFocus()
        }
      }
    }

    Greetd {
    // Face is an explicit action now: nothing scans at startup. Pressing Enter on
    // an empty field is what asks for a face (LockInput.onAccepted -> faceRequested
    // -> begin()), typing a password skips it. Auto-scanning on launch logged
    // people in just for walking past the camera, and it also hid whether the
    // password path worked. GREETER_AUTOBEGIN=1 restores the old behaviour
    // (the smoke suite uses it for the passwordless cases).
    autoBegin: (Quickshell.env("GREETER_AUTOBEGIN") || "") === "1"
      id: greetd
      username: lastUser.remembered.length > 0
        ? lastUser.remembered
        : (Quickshell.env("GREETER_USER") || "")
      session: Quickshell.env("GREETER_SESSION") || "niri-session"
      avatarPath: {
        var i = accounts.indexOfUser(greetd.username)
        return i >= 0 ? accounts.users[i].avatar : ""
      }
      onUsernameChanged: window.applyAccountLook()
      onStarted: Quickshell.execDetached([
        "sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"",
        "sh", window.stateDir + "/last-user", greetd.username
      ])
    }

    // Evidence that the keyboard actually reaches this surface: the password
    // field is empty until someone types into it. Logged once per fill, never
    // the value or its length.
    property bool sawPasswordInput: false

    Split {
      id: design
      anchors.fill: parent
      backgroundPath: window.accountWallpaper(greetd.username)
      avatarPath: greetd.avatarPath
      loginUser: greetd.username
      // Without this the design treats Enter on an empty field as a no-op:
      // LockInput.onAccepted only asks for a face when lock.faceConfigured is set
      // (Split/DesignBase default it to false). install.sh writes GREETER_FACE=1
      // into niri.kdl when howdy is present.
      faceConfigured: (Quickshell.env("GREETER_FACE") || "") === "1"
      hintOverride: greetd.hint.length > 0
                    ? greetd.hint
                    : "Press Enter for face unlock, or just type your password"
      // The design's own watchdog reclaims focus for the password field whenever
      // it is not focused (DesignBase.qml:213-226), which silently stole every
      // keystroke from the account picker: Tab opened it, arrows and Enter went
      // to the design instead, so switching accounts looked broken. Dropping
      // inputEnabled while the picker is open is the switch that design offers
      // for exactly this, and onInputEnabledChanged refocuses the field after.
      inputEnabled: !greetd.sessionStarting && !picker.open
      authenticatingPassword: greetd.busy
      failureMessage: greetd.errorMessage
      failedAttempts: greetd.failedAttempts
      onPasswordTextChanged: if (!window.sawPasswordInput && design.passwordText.length > 0) {
        window.sawPasswordInput = true
        console.warn("greeter: the password field received input")
      }
      // The host owns passwordText: the design only *emits* passwordTextEdited
      // (DesignBase sets passwordText nowhere). Missing this is why typing
      // showed dots but nothing happened: lock.passwordText stayed "", so
      // LockInput.onAccepted found submitted.length === 0 and fell through to
      // "re-arm the face scan" — Enter looked dead, and so did switching
      // accounts (the field was empty for every account).
      onPasswordTextEdited: text => design.passwordText = text
      onClearFailureRequested: greetd.errorMessage = ""
      onPasswordRequested: Qt.callLater(design.forcePasswordFocus)
      onSubmitPassword: password => {
        // The design keeps the submitted text in passwordText (the lock screen
        // clears it through its own service), so clear it here or the field
        // stays filled with dots after a failed attempt.
        design.passwordText = ""
        window.sawPasswordInput = false
        greetd.authenticate(password)
      }
      // Enter on an empty field: the lock screen re-tries camera/fingerprint
      // with it, the greeter re-arms the face scan.
      onFaceRequested: greetd.begin()
    }

    // The Split design is a lock screen: no account control, and the chip in the
    // corner is easy to miss. Tab opens the picker from anywhere (Escape closes
    // it, see UserPicker).
    Shortcut {
      sequence: "Tab"
      onActivated: {
        console.warn("greeter: Tab was pressed")
        if (!picker.open) picker.show()
      }
    }

    UserPicker {
      id: picker
      anchors.fill: parent
      host: design
      users: accounts.users
      current: greetd.username
      panelWidth: design.panelWidth
      onPicked: name => {
        console.warn("greeter: the account picker chose", name)
        greetd.setUser(name)
        Qt.callLater(design.forcePasswordFocus)
      }
      onDismissed: Qt.callLater(design.forcePasswordFocus)
    }

    // Point the palette at the selected account. Color is a singleton read by
    // every design component, so this is the one place that has to change.
    function applyAccountLook() {
      Color.themeOverride = window.accountTheme(greetd.username)
    }

    Component.onCompleted: applyAccountLook()

    // The design is a lock screen and offers no way to change account, so the
    // greeter adds one: a small always-visible control in the panel's top right.
    Item {
      id: switchButton

      x: window.width - design.margin - width
      y: design.margin
      width: Math.round(Style.font.bodySmall * 12)
      height: Math.round(Style.font.bodySmall * 2.4)

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: hover.hovered
          ? design.withAlpha(Color.lock.text, 0.12)
          : design.withAlpha(Color.lock.text, 0.04)
        border.width: 1
        border.color: design.withAlpha(Color.lock.border, 0.3)
      }

      Text {
        anchors.centerIn: parent
        text: "󰀄  " + greetd.username
        color: design.withAlpha(Color.lock.text, 0.8)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
      }

      HoverHandler { id: hover }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          console.warn("greeter: the account chip was clicked")
          picker.open ? picker.open = false : picker.show()
        }
      }
    }

    // Focus diagnostics: GREETER_DEBUG_FOCUS=1 logs the input field's state and
    // who holds item focus inside the window, once a second. Needed because a
    // login screen that renders correctly but silently ignores the keyboard
    // looks identical from the outside whether the field is disabled, read-only,
    // unfocused, or the surface never got compositor focus.
    Timer {
      interval: 1000
      running: (Quickshell.env("GREETER_DEBUG_FOCUS") || "") === "1"
      repeat: true
      onTriggered: {
        var item = design.inputItem
        console.warn("greeter/diag:",
                     "field=" + (item ? "yes" : "no"),
                     item ? ("enabled=" + item.enabled + " readOnly=" + item.readOnly
                            + " visible=" + item.visible
                            + " activeFocus=" + item.activeFocus
                            + " size=" + Math.round(item.width) + "x" + Math.round(item.height)) : "",
                     "textLen=" + (item ? item.text.length : -1)
                     + " designTextLen=" + design.passwordText.length,
                     "pickerOpen=" + picker.open + " pickerFocus=" + picker.activeFocus)
      }
    }

    // Test hook: only loads when GREETER_SELFTEST_PASSWORD is set, so a greeter
    // change can be validated without logging out of a session.
    Loader {
      active: (Quickshell.env("GREETER_SELFTEST_PASSWORD") || "").length > 0
      source: "SelfTest.qml"
      onLoaded: {
        item.target = design
        item.picker = picker
      }
    }
  }
}
