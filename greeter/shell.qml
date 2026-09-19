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
    WlrLayershell.namespace: "omarchy-greeter"
    // Overlay, like the lock screen: it is the only surface in the session, and
    // Exclusive keyboard focus is what niri grants on an overlay layer.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    readonly property string stateDir: (Quickshell.env("HOME") || "/var/lib/greeter") + "/.local/state/omarchy-greeter"
    // Per-account artwork, written by omarchy-greeter-sync: the login screen
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

    Greetd {
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

    Split {
      id: design
      anchors.fill: parent
      backgroundPath: window.accountWallpaper(greetd.username)
      avatarPath: greetd.avatarPath
      loginUser: greetd.username
      hintOverride: greetd.hint
      inputEnabled: !greetd.sessionStarting
      authenticatingPassword: greetd.busy
      failureMessage: greetd.errorMessage
      failedAttempts: greetd.failedAttempts
      onSubmitPassword: password => {
        // The design keeps the submitted text in passwordText (the lock screen
        // clears it through its own service), so clear it here or the field
        // stays filled with dots after a failed attempt.
        design.passwordText = ""
        greetd.authenticate(password)
      }
      // Enter on an empty field: the lock screen re-tries camera/fingerprint
      // with it, the greeter re-arms the face scan.
      onFaceRequested: greetd.begin()
    }

    UserPicker {
      id: picker
      anchors.fill: parent
      host: design
      users: accounts.users
      current: greetd.username
      panelWidth: design.panelWidth
      onPicked: name => {
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
        onClicked: picker.open ? picker.open = false : picker.show()
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
