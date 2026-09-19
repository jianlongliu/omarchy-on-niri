import QtQuick
import Quickshell
import qs.Commons

// Test hook, not part of the login path: loaded only when
// GREETER_SELFTEST_PASSWORD is set (see shell.qml). Drives the design so the
// full quickshell -> bridge -> greetd flow can be exercised inside a running
// session, without logging out.
//
//   GREETER_SELFTEST_PASSWORD=pw        submit that password
//   GREETER_SELFTEST_OPEN_PICKER=1      only open the account picker
//   GREETER_SELFTEST_PICK=<user>        open the picker and choose that account
//   GREETER_SELFTEST_CLICK_AVATAR=1     emit the design's avatarClicked() and
//                                       stop -- the account switcher's host half
//   GREETER_SELFTEST_PASSWORD_DELAY_MS  wait this long before submitting, so a
//                                       test can let the face-scan watchdog fire
Item {
  id: self

  // The Split design instance, i.e. the lock host being driven.
  property Item target: null
  property Item picker: null
  property int delay: 1200
  property string password: Quickshell.env("GREETER_SELFTEST_PASSWORD") || ""
  property bool openPickerOnly: Quickshell.env("GREETER_SELFTEST_OPEN_PICKER") === "1"
  property bool clickAvatarOnly: Quickshell.env("GREETER_SELFTEST_CLICK_AVATAR") === "1"
  property string pick: Quickshell.env("GREETER_SELFTEST_PICK") || ""
  property int passwordDelay: Number(Quickshell.env("GREETER_SELFTEST_PASSWORD_DELAY_MS")) || 0

  function submit() {
    if (!self.target) {
      console.warn("selftest: no target design")
      return
    }
    console.warn("selftest: typing the password for", self.target.userName)
    // Go through the design the way a person does: the field reports edited
    // text, and the field is what submits (LockInput.onAccepted reads
    // lock.passwordText). Calling target.submitPassword() directly skipped the
    // host wiring that passwordTextEdited needs, so a login that could never
    // work passed every test.
    self.target.passwordTextEdited(self.password)
    if (self.target.inputItem) self.target.inputItem.accepted()
  }

  // The palette has to follow the picked account, not the greeter user's HOME.
  // The only way a test can see that is to print what Color resolved.
  Timer {
    id: paletteTimer
    interval: 400
    onTriggered: console.warn("selftest: palette is", Color.background, Color.lock.text,
                              "from", Color.currentThemePath)
  }

  Timer {
    id: lateSubmit
    onTriggered: self.submit()
  }

  Timer {
    interval: self.delay
    running: true
    onTriggered: {
      if (self.clickAvatarOnly) {
        // What the design's own MouseArea emits when the account picture is
        // clicked. A pointer click cannot be injected in this session (no
        // ydotool), so this covers the host half -- onAvatarClicked -> picker --
        // which is the half that can go missing silently.
        console.warn("selftest: clicking the avatar")
        if (self.target) self.target.avatarClicked()
        return
      }
      if (self.pick.length > 0) {
        console.warn("selftest: switching to", self.pick)
        self.picker.picked(self.pick)
        paletteTimer.start()
        return
      }
      if (self.openPickerOnly) {
        console.warn("selftest: opening the account picker")
        self.picker.show()
        return
      }
      if (self.passwordDelay > 0) {
        lateSubmit.interval = self.passwordDelay
        lateSubmit.start()
        return
      }
      self.submit()
    }
  }
}
