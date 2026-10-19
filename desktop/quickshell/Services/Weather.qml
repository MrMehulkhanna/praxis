pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Weather — current conditions from wttr.in (free, no API key). Fetches at
// most every 30 min and only while a consumer holds a reference (active > 0).
// On any network or parse failure the last good values are kept.
Singleton {
    id: root

    property int active: 0

    property string emoji: ""
    // Maps the condition onto the shell's own icon set, so the tile never
    // depends on an emoji font being installed.
    readonly property string icon: {
        const c = cond.toLowerCase()
        if (/thunder|storm/.test(c)) return "bolt"
        if (/clear|sunny/.test(c)) {
            const h = new Date().getHours()
            return (h >= 6 && h < 19) ? "sun" : "moon"
        }
        return "cloud"                     // rain, drizzle, snow, fog, overcast…
    }
    property string tempC: ""
    property string cond: ""
    property string place: ""
    property real   lastFetch: 0         // epoch seconds of the last good fetch

    readonly property int maxAgeSecs: 1800

    function refresh() {
        if (!wttr.running) wttr.running = true
    }

    Timer {
        interval: 60000
        running: root.active > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (Date.now() / 1000 - root.lastFetch > root.maxAgeSecs) root.refresh()
        }
    }

    Process {
        id: wttr
        // %c emoji | %t temperature | %C condition | %l location
        command: ["curl", "-sf", "--max-time", "8", "https://wttr.in/?format=%c|%t|%C|%l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split("|")
                if (parts.length < 4 || parts[1].trim() === "") return
                root.emoji = parts[0].trim()
                root.tempC = parts[1].trim().replace("+", "")
                root.cond = parts[2].trim()
                root.place = parts[3].trim().split(",")[0]
                root.lastFetch = Date.now() / 1000
            }
        }
    }
}
