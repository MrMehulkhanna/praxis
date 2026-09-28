pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Power profiles (power-profiles-daemon), brightness, and session actions.
Singleton {
    id: root

    // ── power profile ──────────────────────────────────────────────────
    property string profile: "balanced"       // power-saver | balanced | performance
    readonly property var profiles: ["power-saver", "balanced", "performance"]

    function refreshProfile() { if (!profProc.running) profProc.running = true }
    function setProfile(p) {
        Quickshell.execDetached(["powerprofilesctl", "set", p])
        root.profile = p
        refreshLater.start()
    }
    Process {
        id: profProc
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector { onStreamFinished: { const t = this.text.trim(); if (t) root.profile = t } }
    }
    Timer { id: refreshLater; interval: 800; onTriggered: root.refreshProfile() }
    Component.onCompleted: refreshProfile()

    // ── brightness ─────────────────────────────────────────────────────
    property real brightness: 0.5              // 0..1
    // Floor for every brightness control. On an OLED panel 0 % switches it
    // fully black (it looks dead), so it keeps 10 %; other screens go to 1 %.
    readonly property real minBrightness: Display.hasOled ? 0.10 : 0.01
    property bool _settingBrightness: false
    function refreshBrightness() { if (!brtProc.running) brtProc.running = true }
    function setBrightness(v) {
        v = Math.max(root.minBrightness, Math.min(1, v))
        root.brightness = v
        if (!brtSet.running) {
            brtSet.command = ["brightnessctl", "-q", "set", Math.round(v * 100) + "%"]
            brtSet.running = true
        } else _pendingBrt = v
    }
    property real _pendingBrt: -1
    Process {
        id: brtSet
        onExited: { if (root._pendingBrt >= 0) { const v = root._pendingBrt; root._pendingBrt = -1; root.setBrightness(v) } }
    }
    Process {
        id: brtProc
        command: ["bash", "-c", "echo $(brightnessctl -m | cut -d, -f4 | tr -d %)"]
        stdout: StdioCollector { onStreamFinished: { const v = parseInt(this.text.trim()); if (!isNaN(v)) root.brightness = v / 100 } }
    }
    Component.onDestruction: {}
    Timer { interval: 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refreshBrightness() }

    // ── session ────────────────────────────────────────────────────────
    function lock()     { Quickshell.execDetached(["hyprlock"]) }
    function suspend()  { Quickshell.execDetached(["systemctl", "suspend"]) }
    function logout()   { Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.exit()"]) }
    function reboot()   { Quickshell.execDetached(["systemctl", "reboot"]) }
    function poweroff() { Quickshell.execDetached(["systemctl", "poweroff"]) }
}
