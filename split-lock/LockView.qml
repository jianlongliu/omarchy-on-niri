// Split lock view — the whole "bridge" between Omarchy's lock service and the
// Split design.
//
// Omarchy's lock Service instantiates `LockView { ... }` *by filename*, so this
// file is the drop-in: naming it LockView.qml is what makes the swap work, and
// `Split {}` makes the root of this file the design itself. Every property the
// Service already sets (failureMessage, failedAttempts, inputEnabled,
// passwordText, backgroundPath, ...) binds straight through: Split declares the
// same names via DesignBase, which was written against this very contract,
// signals included (submitPassword / clearFailureRequested).
//
// The design files (Split, DesignBase, LockInput, PasswordField, Avatar,
// Wallpaper) sit next to this one deliberately: same-directory types resolve
// implicitly, so there is no directory import here to go wrong. With an
// `import "designs"` instead, Split failed to resolve roughly half the time —
// but only when the view was reached as an imported *type*, never as the root
// file of a config. Same directory removes that whole class of failure.
//
// Deliberately NOT wired here: onPasswordTextEdited. The Service already handles
// it (`root.enteredPassword = password`) and binds passwordText: root.enteredPassword
// both ways. Assigning passwordText again from inside the view would destroy
// that binding, and then the Service could no longer clear the field after a
// failed attempt. §11.13's trap is the *negative* of this: there the host never
// handled the signal at all.
import QtQuick
import Quickshell

Split {
  id: view

  // The Service defines these two (Service.qml:34-48) and passes them to the view
  // alongside backgroundVersion (Service.qml:310). DesignBase has no such
  // properties, and without declaring them Quickshell refuses to create the view
  // ("Cannot assign to non-existent property"). Nothing to route them to, and
  // nothing lost: the stock view uses them for exactly one thing, pausing
  // wallpaper playback (reference/LockView.qml:94), and this design's Wallpaper is
  // a static Image (Wallpaper.qml:22) — there is no animation to pause. What does
  // matter, loadBackground and backgroundVersion feeding the cache-busting fileUrl,
  // is already honoured there (Wallpaper.qml:25).
  property bool displaysBlank: false
  property bool powerSaverActive: false

  // Only the password PAM flow exists on this machine (no omarchy-lock-face,
  // no pam_facelock.so, no fido2), so the design's own face/fido2 affordances
  // stay off — offering keys that cannot work is worse than not offering them.
  //
  // Face is no longer hardcoded off (2026-09-20): the host probes howdy behind
  // /etc/pam.d/omarchy-lock-face and drives faceConfigured / faceRequested
  // through here, the way it already drives fingerprint. fido2 stays off — the
  // machine keeps fprint on sudo and polkit only.
  fido2Configured: false
}
