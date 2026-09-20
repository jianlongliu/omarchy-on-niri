import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// Bar-left replacement for omarchy.menu's logo button: the same button, drawn
// as the Arch logo. The menu panel itself is untouched — omarchy.menu is
// keepLoaded, so it stays mounted with its button off the bar.
BarWidget {
  id: root
  moduleName: "jianlongliu.arch-logo"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Omarchy menu"

    iconComponent: Component {
      Item {
        Image {
          id: logo
          anchors.fill: parent
          source: Qt.resolvedUrl("arch-logo.svg")
          sourceSize.width: Math.round(width * Screen.devicePixelRatio)
          sourceSize.height: Math.round(height * Screen.devicePixelRatio)
          fillMode: Image.PreserveAspectFit
          smooth: true
          // Hidden but layered so MultiEffect can sample it as a texture.
          // colorization multiplies by source luminance, so the SVG must be
          // pure white or the logo renders dimmer than its neighbours.
          visible: false
          layer.enabled: true
        }

        MultiEffect {
          anchors.fill: parent
          source: logo
          colorization: 1.0
          colorizationColor: button.foreground
        }
      }
    }

    onPressed: function(btn) {
      if (!root.bar) return
      if (btn === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
