pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Niri-backed replacement for the pieces of Quickshell's `Hyprland` module that
// Omarchy's bar actually reads (Hyprland.workspaces, .focusedWorkspace,
// .focusedMonitor), plus the overview flag BlurWallpaper.qml gates its layer on.
//
// State comes from niri's IPC event stream (`niri msg -j event-stream`) rather
// than the 500 ms polling this used to do. The stream replays the full workspace
// and window lists on connect and then pushes every change, so:
//   * the overview's blurred wallpaper appears with the overview instead of up to
//     half a second later (that delay was the poll interval),
//   * the bar's workspace pills react immediately,
//   * the shell stops spawning ~6 `niri msg` processes per second while idle.
//
// Events carrying partial data (WorkspaceActivated, WindowOpenedOrChanged, ...)
// only trigger a fresh one-shot query of the relevant list, debounced so a burst
// of events costs one spawn instead of one per event.
//
// Workspaces.qml reads .workspaces.values[].id / .toplevels.values.length and
// .focusedWorkspace.id; Bar.qml reads .focusedMonitor.name.
QtObject {
    id: root

    property var workspaces: ({ values: [] })
    property var focusedWorkspace: null
    property var focusedMonitor: null
    property bool overviewOpen: false

    property string _focusedOutput: ""
    property var _winCountById: ({})

    // Re-read both lists from scratch. Used on startup and by the event handlers.
    function refresh() {
        if (!wsProcess.running) wsProcess.running = true
        if (!winProcess.running) winProcess.running = true
    }

    function countArray(n) {
        var a = []
        for (var i = 0; i < n; i++) a.push({})
        return a
    }

    function applyWorkspaces(text) {
        var arr = []
        var fw = null
        try {
            var data = JSON.parse(text)
            for (var i = 0; i < data.length; i++) {
                var w = data[i]
                var item = {
                    "niriId": w.id,
                    "id": w.idx !== undefined ? w.idx : w.id,
                    "name": w.name || "",
                    "output": w.output || "",
                    "active": !!w.is_active,
                    "focused": !!w.is_focused,
                    "toplevels": { values: [] }
                }
                arr.push(item)
                if (w.is_focused) {
                    fw = item
                    root._focusedOutput = w.output || ""
                }
            }
        } catch (e) {
            // ignore malformed/empty output
        }
        root.workspaces = { values: arr }
        root.focusedWorkspace = fw
        root.focusedMonitor = { "name": root._focusedOutput }
        root.applyOccupancy(root._winCountById)
    }

    function applyWindows(text) {
        var byId = {}
        try {
            var wins = JSON.parse(text)
            for (var i = 0; i < wins.length; i++) {
                var wid = wins[i].workspace_id
                byId[wid] = (byId[wid] || 0) + 1
            }
        } catch (e) {}
        root._winCountById = byId
        root.applyOccupancy(byId)
    }

    function applyOccupancy(byId) {
        var ws = root.workspaces && root.workspaces.values ? root.workspaces.values : []
        var out = []
        for (var i = 0; i < ws.length; i++) {
            var w = ws[i]
            var copy = {
                "niriId": w.niriId,
                "id": w.id,
                "name": w.name,
                "output": w.output,
                "active": w.active,
                "focused": w.focused,
                "toplevels": { values: root.countArray(byId[w.niriId] || 0) }
            }
            out.push(copy)
        }
        root.workspaces = { values: out }
    }

    // One line of the event stream (a JSON object with a single key).
    function handleEvent(line) {
        var msg = null
        try {
            msg = JSON.parse(line)
        } catch (e) {
            return
        }
        if (!msg) return

        if (msg.OverviewOpenedOrClosed) {
            root.overviewOpen = !!msg.OverviewOpenedOrClosed.is_open
            return
        }
        if (msg.WorkspacesChanged || msg.WorkspaceActivated || msg.WorkspaceUrgencyChanged
                || msg.WorkspacesReordered)
            wsDebounce.restart()
        if (msg.WindowsChanged || msg.WindowOpenedOrChanged || msg.WindowClosed
                || msg.WorkspaceActivated)
            winDebounce.restart()
    }

    property Process wsProcess: Process {
        id: wsProcess
        command: ["niri", "msg", "-j", "workspaces"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyWorkspaces(text)
        }
        stderr: StdioCollector {}
    }

    property Process winProcess: Process {
        id: winProcess
        command: ["niri", "msg", "-j", "windows"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyWindows(text)
        }
        stderr: StdioCollector {}
    }

    // Coalesce event bursts (a workspace switch emits several events) into one query.
    property Timer wsDebounce: Timer {
        interval: 40
        onTriggered: if (!wsProcess.running) wsProcess.running = true
    }

    property Timer winDebounce: Timer {
        interval: 40
        onTriggered: if (!winProcess.running) winProcess.running = true
    }

    property Process eventStream: Process {
        id: eventStream
        command: ["niri", "msg", "-j", "event-stream"]
        running: true
        stdout: SplitParser {
            onRead: line => root.handleEvent(line)
        }
        stderr: StdioCollector {}
        // niri gone (restart, crash): reconnect after a beat. The stream replays
        // the full state on connect, so no extra resync is needed.
        onExited: streamRetry.restart()
    }

    property Timer streamRetry: Timer {
        interval: 1000
        onTriggered: if (!eventStream.running) eventStream.running = true
    }

    Component.onCompleted: root.refresh()
}
