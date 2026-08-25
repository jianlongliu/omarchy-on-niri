pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Niri-backed replacement for the pieces of Quickshell's `Hyprland` module
// that Omarchy's bar actually reads (Hyprland.workspaces, .focusedWorkspace,
// .focusedMonitor). On niri there is no Hyprland IPC, so this singleton
// polls `niri msg -j workspaces/windows` and exposes an equivalent model.
//
// The shell never needed more than this: Workspaces.qml reads
//   .workspaces.values[].id / .toplevels.values.length  and .focusedWorkspace.id
// Bar.qml reads .focusedMonitor.name
QtObject {
    id: root

    property var workspaces: ({ values: [] })
    property var focusedWorkspace: null
    property var focusedMonitor: null

    property string _focusedOutput: ""
    property int _pollMs: 500
    property var _winCountById: ({})

    function refresh() {
        wsProcess.running = true
        winProcess.running = true
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

    property Timer pollTimer: Timer {
        interval: root._pollMs
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
