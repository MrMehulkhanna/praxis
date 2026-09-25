pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// swaync integration. One subscription process — swaync pushes state
// changes to us, we never poll.
Singleton {
    id: root

    property int  count: 0
    property bool dnd: false
    property bool panelVisible: false

    Process {
        id: sub
        command: ["swaync-client", "-s"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const s = JSON.parse(line)
                    root.count = s.count ?? root.count
                    root.dnd = !!s.dnd
                    root.panelVisible = !!s.visible
                } catch (e) {}
            }
        }
        onExited: restart.start()
    }
    Timer { id: restart; interval: 2000; onTriggered: sub.running = true }

    function togglePanel() { Quickshell.execDetached(["swaync-client", "-t"]) }
    function toggleDnd()   { Quickshell.execDetached(["swaync-client", "-d"]) }
    function clearAll()    { Quickshell.execDetached(["swaync-client", "-C"]) }
    function notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Shell", title, body || ""])
    }
}
