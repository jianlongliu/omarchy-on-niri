import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Blurred wallpaper shown ONLY while the niri overview is open.
//
// niri renders the overview on top of the compositor "backdrop". By default
// that backdrop is a flat dark color; this layer opts into the backdrop via
// the `place-within-backdrop` layer-rule in ~/.config/niri/effects.kdl, so it
// paints the strongly blurred wallpaper behind the window thumbnails instead.
//
// While the overview is closed the surface is unmapped, so the normal desktop
// keeps the crisp wallpaper from Background.qml untouched -- and it can never be
// tinted by this layer. Keeping it mapped instead was measured (2026-09-19) to
// save only ~40 ms of opening latency while costing niri ~2% of a core, so the
// surface still comes and goes with the overview; what is cached is the decode
// (`cache: true` below), which is the expensive part.
//
// The wallpaper link is re-resolved whenever the overview opens, so a theme
// switch since the previous overview is picked up.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property string backgroundPath: ""

  function refresh() {
    if (!linkProc.running) linkProc.running = true
  }

  Process {
    id: linkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p) root.backgroundPath = p
      }
    }
  }

  Connections {
    target: Niri
    function onOverviewOpenChanged() {
      // overview just opened -> resolve the freshest wallpaper link first.
      // backgroundPath is already populated by Component.onCompleted, so the
      // very first overview is painted immediately.
      if (Niri.overviewOpen) root.refresh()
    }
  }

  Component.onCompleted: root.refresh()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"

      visible: Niri.overviewOpen

      // Keep render updates enabled: a parked surface can lose its committed
      // buffer (same lesson as Background.qml), which would show a black
      // backdrop inside the overview.
      updatesEnabled: true

      WlrLayershell.namespace: "omarchy-blurwallpaper"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Image {
        id: wallpaper
        anchors.fill: parent
        source: root.backgroundPath ? Util.fileUrl(root.backgroundPath) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // This layer is hidden and shown on every overview toggle. With
        // `cache: false` each open paid for a fresh decode + upload of a
        // full-screen wallpaper, which showed up as the blurred backdrop
        // arriving late; the decode now stays in the shared pixmap cache.
        cache: true
        smooth: true
        mipmap: true

        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
          // Heavy blur (blurMax 32 = 32 logical px ≈ 64 physical px at 2.0 scale).
          blurEnabled: true
          blur: 1.0
          blurMax: 32
          // niri dims the overview backdrop; compensate so the wallpaper keeps
          // its brightness instead of looking muddy.
          brightness: 0.15
        }
      }
    }
  }
}