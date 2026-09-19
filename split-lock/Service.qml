import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property bool lockRequested: false
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
  // PORT (split-lock): face unlock on the lock screen, off the same design
  // affordances upstream already carries (faceConfigured / faceRequested) but
  // as its own PAM service, so a slow scan can never sit in front of the
  // password path. Enter-triggered only -- see README, "Face unlock".
  property bool faceConfigured: false
  property bool faceAuthenticating: false
  // Goes to the design's hintOverride: the scan line while scanning, a short
  // notice after a miss, empty the rest of the time.
  property string faceHint: ""
  // PORT (split-lock): the lock screen's avatar, auto-detected the way the
  // third-party lock did it (~/.config/omarchy/lock-avatar.*, ~/.face,
  // ~/.face.icon, /var/lib/AccountsService/icons/$USER).
  property string avatarPath: ""
  property int avatarVersion: 0
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string lastEvent: "init"
  property string lastEventAt: ""
  property bool displaysBlank: false
  // displaysBlank tracks what the lock asked for; Hyprland reports what each
  // panel actually did. While a video is on show the two are reconciled, so a
  // blank that failed keeps playing and a panel woken behind the lock's back
  // (a resume that kept the same outputs) resumes instead of freezing.
  property var monitorDpms: ({})
  property bool monitorDpmsKnown: false
  readonly property bool videoBackground: Util.isVideoPath(backgroundPath)
  property bool strandedLock: false
  property bool strandedLockResolved: false

  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating
  readonly property var batteryService: shell && shell.services ? shell.firstPartyServiceFor("omarchy.battery") : null
  readonly property bool powerSaverActive: batteryService ? batteryService.powerSaverOnBattery : false

  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  function hasRealScreen() {
    return realScreenCount() > 0
  }

  function queueSessionLock() {
    pendingSessionLock = true
    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early is an orphan behind Hyprland's failsafe. Outputs
  // are often still absent here, so ask until the answer means something.
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (locked || lockRequested) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function recoverStrandedLock() {
    if (!strandedLock || locked || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  // PORT (split-lock)
  function refreshFaceStatus() {
    if (!faceCheckProc.running) faceCheckProc.running = true
  }

  // PORT (split-lock)
  function refreshAvatar() {
    if (!avatarDetectProc.running) avatarDetectProc.running = true
  }

  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintRetryTimer.stop()
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
    // PORT (split-lock)
    abortFaceScan()
  }

  // PORT (split-lock): typing is the password path, so the first keystroke
  // drops the camera scan instead of racing it to the same unlock.
  onEnteredPasswordChanged: if (enteredPassword.length > 0 && facePam.active) abortFaceScan()

  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    resetAuthenticationState()
    lockRequested = true
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
    })

    return true
  }

  function finishUnlock() {
    if (!root.locked && !lockRequested) return

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
  }

  function armBlankTimer() {
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  function runWake() {
    root.displaysBlank = false
    root.monitorDpmsKnown = false
    if (!wakeProcess.running) wakeProcess.running = true
    if (lockRequested) armBlankTimer()
  }

  function runBlank() {
    root.displaysBlank = true
    root.monitorDpmsKnown = false
    if (!blankProcess.running) blankProcess.running = true
  }

  function screenBlank(screenName) {
    var name = String(screenName || "")
    if (!monitorDpmsKnown || !(name in monitorDpms)) return displaysBlank
    return !monitorDpms[name]
  }

  function applyMonitorDpms(text) {
    var monitors
    try {
      monitors = JSON.parse(String(text || ""))
    } catch (error) {
      return
    }
    if (!Array.isArray(monitors)) return

    var dpms = {}
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      if (monitor && monitor.name && !monitor.disabled) dpms[String(monitor.name)] = !!monitor.dpmsStatus
    }
    monitorDpms = dpms
    monitorDpmsKnown = true
  }

  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) {
      // PORT (split-lock): an empty submit is the design's "scan me" gesture
      // (LockInput.onAccepted sends faceRequested, but a design without that
      // branch still reaches here).
      if (password.length === 0 && faceConfigured) root.startFace()
      return
    }
    if (facePam.active) root.abortFaceScan()
    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  function handlePasswordFailure() {
    if (!lockRequested) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    runWake()
  }

  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
    }
  }

  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      finishUnlock()
    } else if (fingerprintConfigured) {
      fingerprintRetryTimer.restart()
    }
  }

  // PORT (split-lock): face is Enter-triggered, never a retry loop -- one scan
  // costs 5-7s of camera and a 38MB model load, and a scan that runs by itself
  // also unlocks for whoever walks past. Same rule the greeter settled on.
  function startFace() {
    if (!lockRequested || !sessionLock.secure || !faceConfigured) return
    if (facePam.active || faceAuthenticating || authenticatingPassword) return

    faceHintTimer.stop()
    faceHint = "Look at the camera…"
    faceAuthenticating = true

    if (!facePam.start()) {
      faceAuthenticating = false
      faceHint = ""
    }
  }

  // Typing is the password path, so it takes the camera out of the way rather
  // than racing it to the same unlock.
  function abortFaceScan() {
    if (facePam.active) facePam.abort()
    faceAuthenticating = false
    faceHintTimer.stop()
    faceHint = ""
  }

  function handleFaceFinished(result) {
    faceAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      faceHint = ""
      finishUnlock()
    } else {
      faceHint = "Face not recognized — type your password"
      faceHintTimer.restart()
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
      }
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested
        loadBackground: root.locked
        displaysBlank: root.screenBlank(lockSurface.screen ? lockSurface.screen.name : "")
        powerSaverActive: root.powerSaverActive
        passwordText: root.enteredPassword
        // PORT (split-lock)
        faceConfigured: root.faceConfigured
        avatarPath: root.avatarPath
        avatarVersion: root.avatarVersion
        hintOverride: root.faceHint
        onPasswordTextEdited: function(password) { root.enteredPassword = password }
        onSubmitPassword: function(password) { root.submitPassword(password) }
        onClearFailureRequested: root.failureMessage = ""
        onWakeRequested: root.runWake()
        onFaceRequested: root.startFace()
      }

    }
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      // PORT (split-lock): the preview is where the avatar and the face
      // affordance get looked at without locking the session.
      faceConfigured: root.faceConfigured
      avatarPath: root.avatarPath
      avatarVersion: root.avatarVersion
      authenticatingPassword: false
      failureMessage: ""
      failedAttempts: 0
      inputEnabled: false
      loadBackground: root.previewVisible
      powerSaverActive: root.powerSaverActive
      passwordText: ""
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.previewVisible = false
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function(result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested) return
      if (result === PamResult.Success) root.finishUnlock()
      else root.handlePasswordFailure()
    }

    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    onError: function(error) {
      root.fingerprintAuthenticating = false
      if (root.lockRequested && root.fingerprintConfigured) fingerprintRetryTimer.restart()
    }
  }

  Timer {
    id: fingerprintRetryTimer
    interval: 250
    repeat: false
    onTriggered: root.startFingerprint()
  }

  // PORT (split-lock): howdy behind its own PAM service. Deliberately separate
  // from omarchy-lock-password -- a scan that hangs (howdy has no client-side
  // deadline of its own once the camera is busy) then costs the face path only,
  // never the password the user is typing.
  PamContext {
    id: facePam
    config: "omarchy-lock-face"
    user: root.userName

    onCompleted: function(result) {
      root.handleFaceFinished(result)
    }

    onError: function(error) {
      root.faceAuthenticating = false
      root.faceHint = "Face auth unavailable — type your password"
      faceHintTimer.restart()
    }
  }

  // The scan line and the post-miss notice are transient; nothing here retries.
  Timer {
    id: faceHintTimer
    interval: 4000
    repeat: false
    onTriggered: root.faceHint = ""
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next !== root.backgroundPath) {
          root.backgroundPath = next
          root.backgroundVersion += 1
        }
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    onExited: {
      root.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && root.fingerprintConfigured) root.startFingerprint()
      else if (!root.fingerprintConfigured && fingerprintPam.active) fingerprintPam.abort()
    }
  }

  // PORT (split-lock): howdy, not facelock -- so the probe asks for the three
  // things a scan actually needs: the PAM service, the module, and a model for
  // *this* user (howdy keeps models as <user>.dat next to its own code).
  Process {
    id: faceCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-face ]] && [[ -f /lib/security/howdy/pam.py ]] && [[ -f /lib/security/howdy/models/$USER.dat ]]; then echo yes; else echo no; fi"]
    stdout: StdioCollector { id: faceCheckStdout; waitForEnd: true }
    onExited: {
      root.faceConfigured = String(faceCheckStdout.text || "").trim() === "yes"
      if (!root.faceConfigured && facePam.active) root.abortFaceScan()
    }
  }

  // PORT (split-lock): where the avatar comes from, in the order the
  // third-party lock used. The first two are the user's own override files,
  // the AccountsService icon is the desktop user picture.
  Process {
    id: avatarDetectProc
    command: ["bash", "-c", "for f in \"$HOME/.config/omarchy/lock-avatar.png\" \"$HOME/.config/omarchy/lock-avatar.jpg\" \"$HOME/.config/omarchy/lock-avatar.jpeg\" \"$HOME/.config/omarchy/lock-avatar.webp\" \"$HOME/.face\" \"$HOME/.face.icon\" \"/var/lib/AccountsService/icons/$USER\"; do [[ -f $f ]] && { echo \"$f\"; exit 0; }; done"]
    stdout: StdioCollector {
      id: avatarDetectOut
      waitForEnd: true
      onStreamFinished: {
        var found = String(avatarDetectOut.text || "").trim().split("\n")[0] || ""
        if (found !== root.avatarPath) {
          root.avatarPath = found
          root.avatarVersion += 1
        }
      }
    }
  }

  Process {
    id: strandedLockCheckProc
    command: ["bash", "-c", "omarchy-hyprland-session-locked"]
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.locked && !root.lockRequested
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  // Quickshell exposes no DPMS signal, so the panel state is polled while a
  // video is the locked wallpaper. A wake or blank request drops the last
  // answer, so its optimistic state applies until the next poll confirms it.
  Process {
    id: monitorDpmsProcess
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root.applyMonitorDpms(text)
    }
  }

  Timer {
    id: monitorDpmsTimer
    interval: 3000
    repeat: true
    triggeredOnStart: true
    running: root.locked && root.videoBackground
    onTriggered: {
      if (!monitorDpmsProcess.running) monitorDpmsProcess.running = true
    }
    onRunningChanged: {
      if (!running) root.monitorDpmsKnown = false
    }
  }

  Timer {
    id: idleBlankTimer
    interval: 5000
    repeat: false
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        root.armBlankTimer()
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword) root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      // A panel coming back is a display turning on that runWake did not ask
      // for, so the blank state has to be given up here or a visible lock
      // wallpaper stays frozen until the next keypress.
      root.displaysBlank = false
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  onAuthenticatingPasswordChanged: {
    if (!lockRequested) return
    if (authenticatingPassword) idleBlankTimer.stop()
    else armBlankTimer()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: {
    refreshBackground()
    refreshFingerprintStatus()
    refreshFaceStatus()
    refreshAvatar()
    checkStrandedLock()
  }

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.locked ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.locked,
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        face: root.faceConfigured,
        faceAuthenticating: root.faceAuthenticating,
        avatar: root.avatarPath,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      // PORT (split-lock): the preview is how the avatar and the face
      // affordance get eyeballed without locking the session.
      root.refreshFaceStatus()
      root.refreshAvatar()
      root.previewVisible = true
      return "ok"
    }

    function hidePreview(): string {
      root.previewVisible = false
      return "ok"
    }
  }
}
