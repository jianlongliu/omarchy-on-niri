// Split lock view — the whole "bridge" between Omarchy's lock service and the
// Split design.
//
// Omarchy's lock Service instantiates `LockView { ... }` *by filename*, so this
// file is the drop-in: naming it LockView.qml is what makes the swap work.
// `import "designs"` + `Split {}` makes the root of this file the design itself,
// so every property the Service already sets (failureMessage, failedAttempts,
// inputEnabled, passwordText, backgroundPath, ...) binds straight through:
// Split declares the same names via DesignBase, which was written against this
// very contract, signals included (submitPassword / clearFailureRequested).
//
// Deliberately NOT wired here: onPasswordTextEdited. The Service already handles
// it (`root.enteredPassword = password`) and binds passwordText: root.enteredPassword
// both ways. Assigning passwordText again from inside the view would destroy
// that binding, and then the Service could no longer clear the field after a
// failed attempt. §11.13's trap is the *negative* of this: there the host never
// handled the signal at all.
import QtQuick
import Quickshell
import "designs"

Split {
  id: view

  // The Service passes these two (Service.qml:318-319) and DesignBase has no
  // such properties: without declaring them Quickshell fails to create the view
  // with "Cannot assign to non-existent property". Accepted and ignored for now;
  // the stock view uses them to blank/park the screen when the session is idle.
  property bool displaysBlank: false
  property bool powerSaverActive: false

  // Only the password PAM flow exists on this machine (no omarchy-lock-face,
  // no pam_facelock.so, no fido2), so the design's own face/fido2 affordances
  // stay off — offering keys that cannot work is worse than not offering them.
  faceConfigured: false
  fido2Configured: false
}
