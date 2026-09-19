import QtQuick
import Quickshell
import Quickshell.Io

// Human accounts on this machine, for the greeter's account picker.
//
// /etc/passwd is world readable, AccountsService's icons directory is world
// readable, and its per-user `users/` directory is not — so the picker is built
// from the passwd entry plus the icon if one exists, not from AccountsService's
// own user list.
Item {
  id: root

  property var users: []
  property bool scanned: false

  signal scanned_all()

  function indexOfUser(name) {
    for (var i = 0; i < users.length; i++)
      if (users[i].name === name) return i
    return -1
  }

  function displayName(name) {
    var i = indexOfUser(name)
    return i >= 0 && users[i].full.length > 0 ? users[i].full : name
  }

  Process {
    id: scan
    running: true
    command: ["sh", "-c",
      "awk -F: '$3>=1000 && $3<65534 && $7 !~ /(nologin|false)$/ {print $1\":\"$5}' /etc/passwd | " +
      "while IFS=: read -r u g; do i=/var/lib/AccountsService/icons/\"$u\"; [ -r \"$i\" ] || i=; " +
      "printf '%s\\t%s\\t%s\\n' \"$u\" \"${g%%,*}\" \"$i\"; done"]
    stdout: SplitParser {
      onRead: line => {
        var parts = line.split("\t")
        if (parts.length < 1 || parts[0].length === 0) return
        var list = root.users.slice()
        list.push({
          name: parts[0],
          full: parts.length > 1 ? parts[1] : "",
          avatar: parts.length > 2 ? parts[2] : ""
        })
        root.users = list
      }
    }
    onExited: {
      root.scanned = true
      root.scanned_all()
    }
  }
}
