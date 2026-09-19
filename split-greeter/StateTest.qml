import QtQuick
import Quickshell

// Display-free harness for the login state machine.
//
// The greeter's own shell.qml needs a compositor (PanelWindow has no backend
// without one), which makes the login path impossible to test from a TTY — the
// exact situation after a wedged login. This harness drives Greetd.qml alone:
// no design, no theme, no window, so it runs with QT_QPA_PLATFORM=offscreen
// against mock-greetd.py. tests/state.sh uses it.
//
//   GREETER_STATE_USER=<account>        account to log in (default tester)
//   GREETER_STATE_PASSWORD=<pw>         submit this password (default: nothing,
//                                       which leaves a passwordless attempt to
//                                       PAM and is how --howdy cases pass)
//   GREETER_STATE_DELAY_MS=<ms>         when to submit (default 1500)
//   GREETER_STATE_SWITCH=<account>      pick another account first (the picker
//                                       path), then submit the password
//   GREETER_ATTEMPT_TIMEOUT_MS=<ms>     forwarded to Greetd.qml
ShellRoot {
  id: root

  property int submitDelay: Number(Quickshell.env("GREETER_STATE_DELAY_MS")) || 1500
  property string password: Quickshell.env("GREETER_STATE_PASSWORD") || ""
  property string switchTo: Quickshell.env("GREETER_STATE_SWITCH") || ""

  Greetd {
    id: welcome
    username: Quickshell.env("GREETER_STATE_USER") || Quickshell.env("GREETER_USER") || "tester"
    session: Quickshell.env("GREETER_SESSION") || "niri-session"
    onStarted: {
      console.warn("statetest: greetd has the session for", welcome.username)
      Qt.quit()
    }
    onErrorMessageChanged: if (welcome.errorMessage.length > 0)
      console.warn("statetest: error:", welcome.errorMessage)
    onFailedAttemptsChanged: if (welcome.failedAttempts > 0)
      console.warn("statetest: failed attempts:", welcome.failedAttempts)
  }

  Timer {
    interval: root.submitDelay
    running: true
    onTriggered: {
      if (root.switchTo.length > 0) {
        console.warn("statetest: switching to", root.switchTo)
        welcome.setUser(root.switchTo)
        submitLater.interval = root.submitDelay
        submitLater.start()
        return
      }
      root.submit()
    }
  }

  Timer {
    id: submitLater
    onTriggered: root.submit()
  }

  function submit() {
    if (root.password.length === 0) return
    console.warn("statetest: submitting the password for", welcome.username)
    welcome.authenticate(root.password)
  }
}
