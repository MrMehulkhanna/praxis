pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "root:/Config"

// System modes, all through `praxis-mode` (the same tool the keybinds and the
// terminal use): the AI on/off, Game mode and Battery saver. The tool keeps
// the state, so this only mirrors it.
Singleton {
    id: root

    property string ai: "on"          // on | off | stopped
    property bool   game: false
    property bool   saver: false
    readonly property bool aiOn: ai !== "off"

    function refresh() { if (!statusProc.running) statusProc.running = true }
    Process {
        id: statusProc
        command: ["praxis-mode", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(this.text)
                    root.ai = s.ai || "on"; root.game = !!s.game; root.saver = !!s.saver
                } catch (e) {}
            }
        }
    }

    property var queue: []
    function run(args) {
        if (cmd.running) { queue = queue.concat([args]); return }
        cmd.command = ["praxis-mode"].concat(args)
        cmd.running = true
    }
    Process {
        id: cmd
        onExited: {
            root.refresh()
            Aios.refresh()
            if (root.queue.length) { const next = root.queue[0]; root.queue = root.queue.slice(1); root.run(next) }
        }
    }

    // optimistic flips so the pills react instantly; refresh() corrects them
    function toggleAi()    { root.ai = root.aiOn ? "off" : "on"; run(["ai", "toggle"]) }
    function toggleGame()  { root.game = !root.game; run(["game", "toggle"]) }
    function toggleSaver() { root.saver = !root.saver; run(["saver", "toggle"]) }

    // charger plugged in / pulled: Battery saver follows, unless switched off in Settings
    function autoSaver() { if (Settings.ready && Settings.autoSaver) run(["saver", "auto"]) }
    Connections { target: UPower; function onOnBatteryChanged() { root.autoSaver() } }
    Connections { target: Settings; function onReadyChanged() { root.autoSaver() } }

    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    IpcHandler {
        target: "modes"
        function ai(): void    { root.toggleAi() }
        function game(): void  { root.toggleGame() }
        function saver(): void { root.toggleSaver() }
    }
}
