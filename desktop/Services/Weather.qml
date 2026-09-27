pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Weather service — hits wttr.in (free, no key) every 30 min while any
// consumer is active. Falls back to empty state on network error.  Cache
// lives in /tmp so it survives a shell reload.
Singleton {
    id: root
    property int active: 0

    property string tempC:  ""
    property string tempF:  ""
    property string cond:   ""
    property string place:  ""
    property string emoji:  ""
    property real   lastFetch: 0

    Timer {
        interval: 60_000
        running: root.active > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const age = Date.now()/1000 - root.lastFetch
            if (age > 30 * 60) root._fetch()
        }
    }

    function _fetch() {
        wttr.running = true
    }

    Process {
        id: wttr
        // ?format=%c|%t|%C|%l — condition emoji | temp | text | location
        command: ["curl", "-sfm", "8", "--max-time", "8", "https://wttr.in/?format=%c|%t|%C|%l"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = String(line).trim().split("|")
                if (parts.length >= 4) {
                    root.emoji = parts[0].trim()
                    root.tempC = parts[1].trim().replace("+","")
                    root.cond  = parts[2].trim()
                    root.place = parts[3].trim().split(",")[0]
                    root.lastFetch = Date.now()/1000
                }
            }
        }
    }
}
