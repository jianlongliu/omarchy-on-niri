import QtQuick
import QtQuick.Effects
import qs.Commons

DesignBase {
  id: lock
  inputItem: field.input

  readonly property int panelWidth: Math.round(Math.max(420, Math.min(560, width * 0.34)))
  readonly property int margin: 56
  readonly property int fieldWidth: panelWidth - margin * 2

  Wallpaper { anchors.fill: parent; lock: lock; blur: 0.0; dim: 0; vignetteTop: 0.25; vignetteMiddle: 0.05; vignetteBottom: 0.45 }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: { lock.wakeRequested(); lock.forcePasswordFocus() }
    onPositionChanged: lock.wakeRequested()
  }

  Column {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: 72
    anchors.bottomMargin: 64
    spacing: 4
    Text {
      text: lock.clock("HH:mm")
      color: Color.lock.text
      font.family: Style.font.family
      font.pixelSize: Math.round(Style.font.baseSize * 8)
      font.weight: Font.DemiBold
      font.letterSpacing: -2
      layer.enabled: true
      layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.6); shadowBlur: 1.0; shadowVerticalOffset: 2 }
    }
    Text {
      text: Qt.formatDate(lock.now, "dddd, d MMMM")
      color: lock.withAlpha(Color.lock.text, 0.85)
      font.family: Style.font.family
      font.pixelSize: Style.font.display
      layer.enabled: true
      layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.6); shadowBlur: 1.0; shadowVerticalOffset: 1 }
    }
  }

  Item {
    id: panel
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: lock.panelWidth
    clip: true

    Wallpaper {
      width: lock.width; height: lock.height
      x: -(lock.width - panel.width)
      lock: lock
      blur: 1.0; dim: 0.2; vignette: false
    }
    Rectangle { anchors.fill: parent; color: lock.withAlpha(Color.lock.background, 0.55) }
    Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: lock.withAlpha(Color.lock.text, 0.14) }

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: lock.margin
      spacing: 22

      Avatar {
        id: avatarBadge
        lock: lock
        width: 84
        fontSize: Math.round(Style.font.baseSize * 3)
        borderWidth: 3
        // greeter patch: the avatar is the account switcher now. The ring
        // brightens on hover so it reads as a control, not a picture.
        borderColor: lock.avatarClickable && avatarHover.hovered
          ? lock.withAlpha(Color.lock.borderActive, 0.9)
          : lock.withAlpha(Color.lock.text, 0.25)
        shadow: false

        HoverHandler {
          id: avatarHover
          enabled: lock.avatarClickable
        }

        MouseArea {
          anchors.fill: parent
          enabled: lock.avatarClickable
          cursorShape: Qt.PointingHandCursor
          onClicked: lock.avatarClicked()
        }
      }

      Column {
        spacing: 4
        Text {
          text: lock.greeting()
          color: lock.withAlpha(Color.lock.text, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.letterSpacing: 2
        }
        Text {
          text: lock.userName
          color: Color.lock.text
          font.family: Style.font.family
          font.pixelSize: Style.font.displayLarge
          font.weight: Font.DemiBold
        }
      }

      PasswordField {
        id: field
        lock: lock
        width: lock.fieldWidth
        height: 58
        textAlignment: TextInput.AlignLeft
        placeholder: "Password"
      }

      Text {
        opacity: lock.snapshotMode ? 0 : 1
        // greeter patch: the face hint is a whole sentence ("...or just type
        // your password") and the panel is only ~323px wide inside its margins,
        // so without this its tail is clipped by the panel.
        objectName: "lockHint"
        width: lock.fieldWidth
        wrapMode: Text.WordWrap
        text: lock.failedAttempts > 0
          ? lock.failedAttempts + " failed " + (lock.failedAttempts === 1 ? "attempt" : "attempts")
          // greeter patch: login, not unlock; and the host can take the line
          // over (face scan running, PAM talking).
          : (lock.hintOverride.length > 0 ? lock.hintOverride
            : (lock.fingerprintConfigured ? "󰆠  Touch the sensor or press Enter" : "Press Enter to log in"))
        color: lock.failedAttempts > 0 ? Color.lock.textError : lock.withAlpha(Color.lock.text, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
      }
    }

    Text {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.margins: lock.margin
      opacity: lock.snapshotMode ? 0 : 1
      text: "󰌾  " + lock.hostName
      color: lock.withAlpha(Color.lock.text, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 2
    }
  }
}
