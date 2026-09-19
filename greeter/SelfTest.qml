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
Item {
  id: self

  // The Split design instance, i.e. the lock host being driven.
  property Item target: null
  property Item picker: null
  property int delay: 1200
  property string password: Quickshell.env("GREETER_SELFTEST_PASSWORD") || ""
  property bool openPickerOnly: Quickshell.env("GREETER_SELFTEST_OPEN_PICKER") === "1"
  property string pick: Quickshell.env("GREETER_SELFTEST_PICK") || ""

  // The palette has to follow the picked account, not the greeter user's HOME.
  // The only way a test can see that is to print what Color resolved.
  Timer {
    id: paletteTimer
    interval: 400
    onTriggered: console.warn("selftest: palette is", Color.background, Color.lock.text,
                              "from", Color.currentThemePath)
  }

  Timer {
    interval: self.delay
    running: true
    onTriggered: {
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
      if (!self.target) {
        console.warn("selftest: no target design")
        return
      }
      console.warn("selftest: submitting password for", self.target.userName)
      self.target.submitPassword(self.password)
    }
  }
}
