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
  property string bridgePath: Quickshell.env("GREETER_BRIDGE") || "/etc/greetd/split-greeter/bridge/greetd-bridge.py"
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
  // Typed before the secret prompt arrived: handed over once it does. It has to
  // live here rather than in the request: greetd's create_session carries no
  // password, and on this machine the first prompt is howdy's (which throws the
  // answer away), so a secret sent "with the login" reaches nobody.
  property string queuedPassword: ""
  // Bumped per login attempt. Replies from an attempt the UI has abandoned
  // (the previous account's face scan finishing after a switch) carry the old
  // epoch and are dropped, then cancelled on greetd's side.
  property int epoch: 0
  property int infoReplies: 0

  // One greetd conversation per connection, and PAM can wedge inside it (howdy
  // waiting on a camera, an info loop). A second request queued behind a stuck
  // one is never delivered, which on the real VT looked exactly like "typing my
  // password does nothing". So an attempt is bounded: on timeout the helper is
  // restarted, which drops the connection and makes greetd cancel the abandoned
  // session, and the fresh connection can go straight to a password.
  property int attemptTimeoutMs: Number(Quickshell.env("GREETER_ATTEMPT_TIMEOUT_MS")) || 12000
  // Auto-start a passwordless (face) attempt as soon as the helper is up.
  property bool autoBegin: true
  // Typed while a face attempt was in flight: delivered on the fresh connection.
  property string pendingPassword: ""
  property bool restarting: false

  readonly property string hint: sessionStarting
    ? "Starting your session…"
    : (faceAttempt ? "Look at the camera, or type your password" : "")

  signal started()

  // Everything here is logged through console.warn: the greeter owns a VT, so
  // $HOME/greeter.log (see niri.kdl) is the only way to see what a login attempt
  // actually did. Never log the password itself.
  function begin() {
    if (root.sessionStarting) return
    // Enter on an empty field asks for a face, but only when there is nothing
    // to ask into: greetd holds one session under configuration for the whole
    // daemon, so a second create_session is refused ("a session is already
    // being configured") and it would also throw away the prompt the user is
    // answering. Pressing Enter twice during a scan is exactly how tty1 wedged
    // on 2026-09-20.
    if (root.busy || root.faceAttempt || root.awaitingSecret) return
    console.warn("greeter: starting a passwordless (face) attempt for", root.username)
    root.epoch += 1
    root.errorMessage = ""
    root.awaitingSecret = false
    root.queuedPassword = ""
    root.infoReplies = 0
    root.faceAttempt = true
    root.busy = true
    root.autoBegin = true
    attemptWatchdog.restart()
    root.command({ op: "auth", epoch: root.epoch, username: root.username })
  }

  // Drop the helper (and with it greetd's connection and the stuck session) and
  // bring up a fresh one. The next request on the new connection is the first
  // one greetd sees, so nothing is queued behind the abandoned attempt.
  function restartHelper(reason) {
    if (root.restarting) return
    root.restarting = true
    root.faceAttempt = false
    root.busy = false
    root.infoReplies = 0
    attemptWatchdog.stop()
    if (reason.length > 0) {
      console.warn("greeter: restarting the login helper —", reason)
      root.errorMessage = ""
    }
    bridge.running = false
    bridgeRestartTimer.restart()
  }

  function onAttemptTimeout() {
    // PAM never answered the passwordless attempt. The fresh connection has no
    // conversation yet, so the next password goes out as a create_session (with
    // the password) rather than as a response to a prompt that does not exist.
    root.autoBegin = false
    root.restartHelper("no answer from greetd in " + Math.round(root.attemptTimeoutMs / 1000) + "s")
  }

  function setUser(name) {
    console.warn("greeter: account switched to", name, "from", root.username)
    root.username = name
    root.failedAttempts = 0
    root.awaitingSecret = false
    root.faceAttempt = false
    root.pendingPassword = ""
    if (root.busy || bridgeRestartTimer.running)
      root.restartHelper("account switched to " + name)
    else
      root.begin()
  }

  function authenticate(password) {
    if (password.length === 0 || root.sessionStarting) return
    console.warn("greeter: password submitted for", root.username,
                 "(", password.length, "chars; awaitingSecret =", root.awaitingSecret,
                 ", faceAttempt =", root.faceAttempt, ")")
    root.busy = true
    if (root.awaitingSecret) {
      root.command({ op: "respond", epoch: root.epoch, response: password })
    } else if (root.faceAttempt) {
      // A face scan is in flight. Instead of waiting for a secret prompt that
      // may never come, drop the connection and answer on a fresh one — typing
      // a password always works.
      root.autoBegin = false
      root.pendingPassword = password
      root.restartHelper("password entered while the face scan was running")
    } else {
      root.errorMessage = ""
      // Hold it: the login starts here, but PAM's first prompt may be howdy's.
      root.queuedPassword = password
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
    attemptWatchdog.stop()
    console.warn("greeter: event", event.event, event.kind || "",
                 event.description || event.message || "", "epoch", event.epoch)
    switch (event.event) {
    case "ready":
      root.ready = true
      root.restarting = false
      if (root.pendingPassword.length > 0) {
        var typed = root.pendingPassword
        root.pendingPassword = ""
        root.busy = true
        root.epoch += 1
        attemptWatchdog.restart()
        root.queuedPassword = typed
        root.command({ op: "auth", epoch: root.epoch, username: root.username, password: typed })
      } else if (root.autoBegin) {
        root.begin()
      } else {
        root.busy = false
      }
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
          attemptWatchdog.restart()
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
        attemptWatchdog.restart()
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

  Timer {
    id: attemptWatchdog
    interval: root.attemptTimeoutMs
    onTriggered: root.onAttemptTimeout()
  }

  // The helper needs a moment to die and release the socket before a new one
  // can connect.
  Timer {
    id: bridgeRestartTimer
    interval: 250
    onTriggered: bridge.running = true
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
      if (root.restarting || root.sessionStarting) return
      root.busy = false
      root.errorMessage = "the login helper exited (code " + code + ")"
    }
  }
}
