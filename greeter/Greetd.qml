import QtQuick
import Quickshell
import Quickshell.Io

// Wraps bridge/greetd-bridge.py: one long-lived python process that speaks line
// JSON to us and greetd's length-prefixed JSON to GREETD_SOCK.
//
// The login is face-first. PAM decides what "face-first" means: on this machine
// /etc/pam.d/greetd runs `ir-light` then howdy as `sufficient` before
// system-local-login. A passwordless create_session therefore starts a face
// scan, and only if that misses does PAM ask for a secret — which is the
// prompt this UI answers with the password field. On a machine without howdy
// the secret prompt arrives immediately and the field is simply always live.
Item {
  id: root

  property string username: ""
  property string session: "niri-session"
  property string avatarPath: ""
  property string bridgePath: Quickshell.env("GREETER_BRIDGE") || "/etc/greetd/omarchy-greeter/bridge/greetd-bridge.py"
  property string sessionEnv: "XDG_SESSION_TYPE=wayland"

  property bool ready: false
  property bool busy: false
  property bool sessionStarting: false
  property string errorMessage: ""
  property int failedAttempts: 0

  // Face scan in progress: PAM has not asked for a secret yet.
  property bool faceAttempt: false
  // PAM is waiting for a secret (howdy missed, or there is no howdy at all).
  property bool awaitingSecret: false
  // Typed before the secret prompt arrived: handed over once it does.
  property string queuedPassword: ""
  // Bumped per login attempt. Replies from an attempt the UI has abandoned
  // (the previous account's face scan finishing after a switch) carry the old
  // epoch and are dropped, then cancelled on greetd's side.
  property int epoch: 0
  property int infoReplies: 0

  readonly property string hint: sessionStarting
    ? "Starting your session…"
    : (faceAttempt ? "Look at the camera, or type your password" : "")

  signal started()

  function begin() {
    if (root.sessionStarting) return
    root.epoch += 1
    root.errorMessage = ""
    root.awaitingSecret = false
    root.queuedPassword = ""
    root.infoReplies = 0
    root.faceAttempt = true
    root.busy = true
    root.command({ op: "auth", epoch: root.epoch, username: root.username })
  }

  function setUser(name) {
    root.username = name
    root.failedAttempts = 0
    root.awaitingSecret = false
    root.faceAttempt = false
    root.begin()
  }

  function authenticate(password) {
    if (password.length === 0 || root.sessionStarting) return
    root.busy = true
    if (root.awaitingSecret) {
      root.command({ op: "respond", epoch: root.epoch, response: password })
    } else if (root.faceAttempt) {
      // A face scan is already running and the bridge is blocked on PAM, so the
      // password waits for the secret prompt instead of opening a second
      // conversation.
      root.queuedPassword = password
    } else {
      root.errorMessage = ""
      root.command({ op: "auth", epoch: root.epoch, username: root.username, password: password })
    }
  }

  function command(request) {
    bridge.write(JSON.stringify(request) + "\n")
  }

  function handle(line) {
    var event
    try {
      event = JSON.parse(line)
    } catch (e) {
      console.warn("greeter: unparseable bridge line:", line)
      return
    }
    if (event.epoch !== undefined && event.epoch !== root.epoch) {
      // The account changed while this attempt was in flight. A PAM success
      // belongs to the account that was current then, so discard the session
      // rather than logging in the wrong user.
      if (event.event === "auth_ok") {
        console.warn("greeter: dropping a login for", root.username, "from a stale attempt")
        root.command({ op: "cancel" })
      }
      return
    }
    switch (event.event) {
    case "ready":
      root.ready = true
      root.begin()
      break
    case "auth_message":
      root.busy = false
      if (event.kind === "secret" || event.kind === "visible") {
        root.faceAttempt = false
        root.awaitingSecret = true
        if (root.queuedPassword.length > 0) {
          var queued = root.queuedPassword
          root.queuedPassword = ""
          root.busy = true
          root.command({ op: "respond", epoch: root.epoch, response: queued })
        }
      } else {
        // info/error: howdy announcing itself, or PAM talking. The conversation
        // only advances when it is answered, so acknowledge and keep the face
        // attempt alive.
        if (root.infoReplies >= 8) {
          root.faceAttempt = false
          root.errorMessage = event.message || "Authentication did not finish"
          return
        }
        root.infoReplies += 1
        root.busy = true
        root.command({ op: "respond", epoch: root.epoch })
      }
      break
    case "auth_ok":
      root.busy = false
      root.errorMessage = ""
      root.faceAttempt = false
      root.awaitingSecret = false
      root.queuedPassword = ""
      root.sessionStarting = true
      root.command({ op: "start", epoch: root.epoch, cmd: [root.session], env: [root.sessionEnv] })
      break
    case "auth_fail":
      root.busy = false
      root.faceAttempt = false
      root.awaitingSecret = false
      root.queuedPassword = ""
      root.failedAttempts += 1
      root.errorMessage = event.description || "Authentication failed"
      break
    case "started":
      // greetd starts the session once this greeter tree is gone.
      root.started()
      // Quickshell 0.3.1 has no quit(); Qt.quit() ends the shell, and the
      // greeter's niri instance follows it out (see niri.kdl), which is what
      // greetd waits for before starting the user's session.
      Qt.quit()
      break
    case "start_failed":
    case "error":
      root.busy = false
      root.sessionStarting = false
      root.errorMessage = event.description || "Could not start the session"
      break
    }
  }

  Process {
    id: bridge
    command: ["python3", root.bridgePath]
    stdinEnabled: true
    running: true
    stdout: SplitParser {
      onRead: line => root.handle(line)
    }
    stderr: SplitParser {
      onRead: line => console.warn("greeter/bridge:", line)
    }
    onExited: (code, status) => {
      if (!root.sessionStarting)
        root.errorMessage = "the login helper exited (code " + code + ")"
    }
  }
}
