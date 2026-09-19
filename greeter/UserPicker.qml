import QtQuick
import qs.Commons
import "designs"

// Account picker for the greeter. The Split design is a lock screen and has no
// such affordance, so this overlays the design's right-hand panel with one row
// per human account.
FocusScope {
  id: picker

  // The design instance, for its withAlpha() and palette access.
  property var host: null
  property var users: []
  property string current: ""
  property bool open: false
  property int cursor: 0
  // Matches the design's own panel width so the slab lands where the lock
  // screen's panel is.
  property real panelWidth: 560

  signal picked(string name)
  signal dismissed()

  function show() {
    var i = 0
    for (var j = 0; j < users.length; j++)
      if (users[j].name === current) i = j
    cursor = i
    open = true
    forceActiveFocus()
  }

  function choose(index) {
    if (index < 0 || index >= users.length) return
    open = false
    picked(users[index].name)
  }

  function move(step) {
    if (users.length === 0) return
    cursor = (cursor + step + users.length) % users.length
  }

  visible: open

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Down) { move(1); event.accepted = true }
    else if (event.key === Qt.Key_Up) { move(-1); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { choose(cursor); event.accepted = true }
    else if (event.key === Qt.Key_Escape) { open = false; dismissed(); event.accepted = true }
  }

  Rectangle {
    anchors.fill: parent
    color: "black"
    opacity: 0.45

    MouseArea {
      anchors.fill: parent
      onClicked: {
        picker.open = false
        picker.dismissed()
      }
    }
  }

  Rectangle {
    id: slab

    x: picker.width - picker.panelWidth
    width: picker.panelWidth
    height: picker.height
    color: picker.host ? picker.host.withAlpha(Color.lock.background, 0.94) : Color.lock.background
    border.width: 1
    border.color: picker.host ? picker.host.withAlpha(Color.lock.text, 0.14) : Color.lock.border

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: 56
      spacing: 10

      Text {
        text: "Choose an account"
        color: picker.host ? picker.host.withAlpha(Color.lock.text, 0.7) : Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.letterSpacing: 2
      }

      Repeater {
        model: picker.users

        Rectangle {
          id: row

          required property var modelData
          required property int index

          width: slab.width - 112
          height: 72
          radius: Style.cornerRadius
          color: index === picker.cursor
            ? (picker.host ? picker.host.withAlpha(Color.lock.borderActive, 0.16) : "transparent")
            : "transparent"
          border.width: index === picker.cursor ? 1 : 0
          border.color: picker.host ? picker.host.withAlpha(Color.lock.borderActive, 0.6) : Color.lock.borderActive

          // Follow the pointer only on real motion. A stationary mouse that
          // happens to sit over a row gets a hover-enter the moment the panel
          // appears, which silently undid every arrow-key press: the account
          // that got chosen was the one under the cursor, not the highlighted
          // one. onPositionChanged fires for movement only.
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: picker.cursor = row.index
            onClicked: picker.choose(row.index)
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: 12
            spacing: 14

            Avatar {
              width: 48
              height: 48
              anchors.verticalCenter: parent.verticalCenter
              source: row.modelData.avatar.length > 0 ? "file://" + row.modelData.avatar : ""
              initial: row.modelData.name.charAt(0).toUpperCase()
              shadow: false
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2

              Text {
                text: row.modelData.full.length > 0 ? row.modelData.full : row.modelData.name
                color: Color.lock.text
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
              }
              Text {
                visible: row.modelData.full.length > 0
                text: row.modelData.name
                color: picker.host ? picker.host.withAlpha(Color.lock.text, 0.55) : Color.lock.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }

      Text {
        text: "↑↓ choose · Enter confirm · Esc cancel"
        color: picker.host ? picker.host.withAlpha(Color.lock.text, 0.45) : Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
      }
    }
  }
}
