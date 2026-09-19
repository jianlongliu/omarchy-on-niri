// Mock host for the Split lock view: it reproduces exactly what Omarchy's own
// lock service does (Service.qml:306-323) — property bindings plus every
// handler the service connects (passwordTextEdited / submitPassword /
// clearFailureRequested / wakeRequested / faceRequested) — and then asserts the
// wires. Run it through tests/state.sh, which assembles a temp tree with
// symlinks for qs.Commons and qs.Ui (in production the shell provides those
// modules; standalone they must be resolvable by name).
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
// tests/state.sh assembles a throwaway config tree with this file, LockView.qml,
// the design files and the shell's Commons/Ui side by side, so the relative
// import below resolves there (that layout, not this one, is what the test runs).
import "." as Lock

ShellRoot {
  id: root

  // Mirrors the service's state.
  property string enteredPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool authenticating: false
  property bool inputEnabled: true
  property string backgroundPath: ""
  property string submitted: ""
  property bool woke: false
  property int checks: 0
  property int failures: 0
  // PORT (split-lock): the two things this port adds to the host.
  property bool faceConfigured: false
  property string avatarPath: ""
  property int avatarVersion: 0
  property string hintOverride: ""
  property int faceRequests: 0

  function check(name, got, want) {
    root.checks++
    if (String(got) === String(want)) {
      console.warn("lockhost: ok   " + name + " = " + got)
    } else {
      root.failures++
      console.warn("lockhost: FAIL " + name + " got '" + got + "' want '" + want + "'")
    }
  }

  // The design's hint line has an objectName (Split.qml) so the wording can be
  // asserted without a screenshot.
  function findChild(item, name) {
    var kids = item ? item.children : null
    for (var i = 0; kids && i < kids.length; i++) {
      var kid = kids[i]
      if (kid.objectName === name) return kid
      var deeper = root.findChild(kid, name)
      if (deeper) return deeper
    }
    return null
  }

  // A plain Rectangle, not the Service's PanelWindow: instantiating a layer-shell
  // window needs a real backend and QT_QPA_PLATFORM=offscreen has none ("No
  // PanelWindow backend loaded"). What is under test is the property and signal
  // wiring, which does not care what the view is parented to.
  Rectangle {
    anchors.fill: parent
    color: Color.background

    Lock.LockView {
      id: lockView
      anchors.fill: parent

      // The service's bindings, verbatim.
      backgroundPath: root.backgroundPath
      backgroundVersion: 0
      fingerprintConfigured: false
      authenticatingPassword: root.authenticating
      failureMessage: root.failureMessage
      failedAttempts: root.failedAttempts
      inputEnabled: root.inputEnabled
      loadBackground: true
      displaysBlank: false
      powerSaverActive: false
      passwordText: root.enteredPassword
      // PORT (split-lock): the bindings the service added alongside the above.
      faceConfigured: root.faceConfigured
      avatarPath: root.avatarPath
      avatarVersion: root.avatarVersion
      hintOverride: root.hintOverride

      // The service's handlers, verbatim (Service.qml:321-324).
      onPasswordTextEdited: function(password) { root.enteredPassword = password }
      onSubmitPassword: function(password) { root.submitted = password }
      onClearFailureRequested: root.failureMessage = ""
      onWakeRequested: root.woke = true
      onFaceRequested: root.faceRequests++
    }
  }

  Timer {
    interval: 1200
    running: true
    repeat: false
    onTriggered: {
      // 1. The view came up at all: the service passes displaysBlank and
      //    powerSaverActive, which DesignBase doesn't declare. Without the
      //    wrapper's declarations Quickshell never creates the view.
      root.check("view instantiated", lockView !== null, true)

      // 2. Host -> view: the service owns enteredPassword and pushes it in.
      root.enteredPassword = "not-a-real-password"
      root.check("host push reaches view", lockView.passwordText, "not-a-real-password")

      // 3. View -> host: the design only emits, the host stores.
      lockView.passwordTextEdited("typed-by-design")
      root.check("design edit reaches host", root.enteredPassword, "typed-by-design")

      // 4. Submitting: the design emits, the service authenticates.
      lockView.submitPassword("hunter2")
      root.check("submit carries the text", root.submitted, "hunter2")

      // 5. Failure state flows in and the design shows it.
      root.failureMessage = "Authentication failed (1)"
      root.failedAttempts = 1
      root.check("failure reaches view", lockView.failureMessage, "Authentication failed (1)")
      root.check("attempts reach view", lockView.failedAttempts, 1)

      // 6. Clearing must still work. If the view ever assigned passwordText
      //    itself, it would have destroyed the host's binding and this would
      //    silently keep the old text (that is §11.13 in mirror image).
      root.enteredPassword = ""
      root.check("host clear reaches view", lockView.passwordText, "")

      // 7. The clear-failure request goes back out.
      lockView.clearFailureRequested()
      root.check("clear-failure reaches host", root.failureMessage, "")

      // 8. Waking goes back out too (the service unblanks the outputs on it).
      lockView.wakeRequested()
      root.check("wake reaches host", root.woke, true)

      // 9-14. PORT (split-lock): the face and avatar wiring, which is what this
      // port adds to the service. Same rule as §11.13/§11.14: drive what the
      // *design* emits, never the host's own helper.
      root.faceConfigured = true
      root.check("face flag reaches view", lockView.faceConfigured, true)

      root.avatarPath = "/tmp/mock-avatar.png"
      root.check("avatar resolves to a file url", lockView.avatarUrl, "file:///tmp/mock-avatar.png?v=0")
      root.avatarVersion = 3
      root.check("avatar version busts the cache", lockView.avatarUrl, "file:///tmp/mock-avatar.png?v=3")

      // Enter on an empty field is the design's own "scan me" gesture
      // (LockInput.onAccepted -> faceRequested), not a host call.
      root.failedAttempts = 0
      root.enteredPassword = ""
      lockView.inputItem.accepted()
      root.check("empty Enter asks for a face scan", root.faceRequests, 1)

      var hint = root.findChild(lockView, "lockHint")
      root.check("hint offers face unlock", hint ? hint.text.indexOf("Press Enter for face unlock") >= 0 : "<no lockHint>", true)

      root.hintOverride = "Look at the camera…"
      root.check("host hint wins while scanning", hint ? hint.text : "<no lockHint>", "Look at the camera…")

      console.warn("lockhost: RESULT checks=" + root.checks + " failures=" + root.failures)
      Qt.exit(root.failures === 0 ? 0 : 1)
    }
  }
}
