pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "root:/Config"

// Global UI state: which overlay is open, which screen overlays appear on,
// and the IPC entry points Hyprland keybinds use.
Singleton {
    id: root

    // "" | "launcher" | "cc" | "ai" | "settings"
    property string overlay: ""
    property string settingsSection: "General"

    function toggle(name) { overlay = (overlay === name) ? "" : name }
    function open(name)  { overlay = name }
    function closeAll()  { overlay = "" }

    // overlays follow the focused monitor (or a pinned one, for demos/automation)
    property string pinnedMonitor: ""
    readonly property var activeScreen: {
        const fm = Hyprland.focusedMonitor
        const scr = Quickshell.screens
        const want = pinnedMonitor || (fm ? fm.name : "")
        if (want) for (let i = 0; i < scr.length; i++) if (scr[i].name === want) return scr[i]
        return scr.length ? scr[0] : null
    }

    // `quickshell ipc call shell toggle launcher`
    property string launcherPrefill: ""
    IpcHandler {
        target: "shell"
        function toggle(name: string): void { root.toggle(name) }
        function open(name: string): void { root.open(name) }
        function close(): void { root.closeAll() }
        // automation / demo hooks
        function ask(text: string): void { root.open("ai"); Aios.send(text) }
        function control(text: string): void { root.open("ai"); Aios.control(text) }
        function search(text: string): void { root.launcherPrefill = text; root.open("launcher") }
        function settings(section: string): void { root.settingsSection = section; root.open("settings") }
        function profile(name: string): void { Settings.profile = name }
        function pin(monitor: string): void { root.pinnedMonitor = monitor === "none" ? "" : monitor }
    }

    // Legacy named-pipe path — existing hyprland.lua binds write here.
    Process {
        id: pipe
        command: ["bash", "-c", "rm -f /tmp/qs-ipc-pipe; mkfifo /tmp/qs-ipc-pipe; exec tail -f /tmp/qs-ipc-pipe"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                switch (line.trim()) {
                    case "spotlight":
                    case "launchpad": root.toggle("launcher"); break
                    case "aichat":    root.toggle("ai"); break
                    case "cc":        root.toggle("cc"); break
                    case "settings":  root.toggle("settings"); break
                    case "activity":  root.toggle("activity"); break
                    case "close":     root.closeAll(); break
                }
            }
        }
        onExited: running = true
    }

    // profiles change real system state, not just colours
    Connections {
        target: Settings
        function onProfileChanged() {
            switch (Settings.profile) {
                case "Development":  Power.setProfile("performance"); if (Notifs.dnd) Notifs.toggleDnd(); break
                case "Cyber Lab":    Power.setProfile("balanced");    if (Notifs.dnd) Notifs.toggleDnd(); break
                case "Presentation": Power.setProfile("balanced");    if (!Notifs.dnd) Notifs.toggleDnd(); Settings.animations = 0.7; break
                default:             Power.setProfile("balanced");    if (Notifs.dnd) Notifs.toggleDnd(); Settings.animations = 1.0
            }
        }
    }

    // launching helpers used by dock / launcher / voice
    function launch(entry) {
        if (!entry) return
        entry.execute()
        overlay = ""
    }
    function run(cmd) { Quickshell.execDetached(["bash", "-lc", cmd]) }
}
