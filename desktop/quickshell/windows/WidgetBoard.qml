import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "root:/Config"
import "root:/Services"
import "root:/components"

// Widget board — a StandBy-style glance screen (SUPER+B).
//
//   ┌──────────── clock ────────────┐┌─────────── calendar ──────────┐
//   ├─ battery ─┬─ system ─┬─ disk ─┬─ weather ─┤
//   ├──────────── media ────────────┼─ network ─┬─ uptime ─┤
//
// Every tile reads from a singleton service (Sys, Battery, Weather, Net) or
// from this window's own properties, referenced by id. Services only poll
// while the board is open (refcounted via onOpened / onOpenChanged).
OverlayWindow {
    id: win
    name: "widgets"

    onOpened: { Sys.active++; Weather.active++; uptimeProc.running = true }
    onOpenChanged: if (!open) {
        Sys.active = Math.max(0, Sys.active - 1)
        Weather.active = Math.max(0, Weather.active - 1)
    }

    readonly property int unit: 232
    readonly property int gap: 16
    readonly property int wide: unit * 2 + gap
    readonly property int rowTall: 212
    readonly property int rowStd: 176

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // ── uptime + kernel (cheap one-shot probe, refreshed while open) ────────
    property string uptimeStr: ""
    property string kernel: ""
    Process {
        id: uptimeProc
        command: ["bash", "-c", "cut -d' ' -f1 /proc/uptime; uname -r"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n")
                const s = parseFloat(lines[0] || "0")
                const d = Math.floor(s / 86400)
                const h = Math.floor((s % 86400) / 3600)
                const m = Math.floor((s % 3600) / 60)
                win.uptimeStr = d > 0 ? `${d}d ${h}h ${m}m` : `${h}h ${m}m`
                win.kernel = lines[1] || ""
            }
        }
    }
    Timer { interval: 30000; running: win.open; repeat: true; onTriggered: uptimeProc.running = true }

    // ── active media player (prefer the one that is playing) ────────────────
    readonly property var player: Mpris.players.values.length
        ? (Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0])
        : null

    function fmtRate(bps) {
        if (bps < 1024) return Math.round(bps) + " B/s"
        if (bps < 1048576) return (bps / 1024).toFixed(0) + " KB/s"
        return (bps / 1048576).toFixed(1) + " MB/s"
    }

    // shared tile chrome
    component Caption: Text {
        color: Theme.muted
        font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase; font.letterSpacing: 0.8
        anchors { top: parent.top; left: parent.left; topMargin: 14; leftMargin: 16 }
    }

    GridLayout {
        anchors.centerIn: parent
        columns: 4
        rowSpacing: win.gap
        columnSpacing: win.gap
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Theme.easePop; easing.overshoot: Theme.popOvershoot } }

        // ── 1 · clock ───────────────────────────────────────────────────────
        Glass {
            Layout.columnSpan: 2
            Layout.preferredWidth: win.wide; Layout.preferredHeight: win.rowTall
            radius: Theme.radiusXl
            Column {
                anchors.centerIn: parent
                spacing: 2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, Settings.clock24h ? "HH:mm" : "h:mm")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 104; font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, "dddd, d MMMM") + (Settings.clock24h ? "" : "  ·  " + Qt.formatDateTime(clock.date, "AP"))
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: Theme.fontMd; font.weight: Font.Medium
                }
            }
        }

        // ── 2 · calendar ────────────────────────────────────────────────────
        Glass {
            id: calTile
            Layout.columnSpan: 2
            Layout.preferredWidth: win.wide; Layout.preferredHeight: win.rowTall
            radius: Theme.radiusXl
            readonly property int year: clock.date.getFullYear()
            readonly property int month: clock.date.getMonth()
            readonly property int today: clock.date.getDate()
            readonly property int firstDow: new Date(year, month, 1).getDay()
            readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
            readonly property int daysLeftInYear: {
                const end = new Date(year, 11, 31)
                return Math.round((end - new Date(year, month, today)) / 86400000)
            }

            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 18

                // big day number
                Column {
                    width: 130
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        text: calTile.today
                        color: Theme.red
                        font.family: Theme.font; font.pixelSize: 72; font.weight: Font.Bold
                    }
                    Text {
                        text: Qt.formatDateTime(clock.date, "MMMM")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.fontLg; font.weight: Font.DemiBold
                    }
                    Text {
                        text: calTile.daysLeftInYear + " days left this year"
                        color: Theme.muted
                        font.family: Theme.font; font.pixelSize: Theme.fontXs
                    }
                }

                // month grid
                Grid {
                    anchors.verticalCenter: parent.verticalCenter
                    columns: 7
                    columnSpacing: 2
                    rowSpacing: 1
                    Repeater {
                        model: ["S", "M", "T", "W", "T", "F", "S"]
                        Text {
                            width: 36; height: 18
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: Theme.muted
                            font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.Bold
                        }
                    }
                    Repeater {
                        model: calTile.firstDow
                        Item { width: 36; height: 22 }
                    }
                    Repeater {
                        model: calTile.daysInMonth
                        Rectangle {
                            required property int index
                            readonly property bool isToday: index + 1 === calTile.today
                            width: 36; height: 22; radius: 11
                            color: isToday ? Theme.red : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: parent.index + 1
                                color: parent.isToday ? "white" : Theme.text
                                font.family: Theme.fontMono; font.pixelSize: 11
                                font.weight: parent.isToday ? Font.Bold : Font.Normal
                            }
                        }
                    }
                }
            }
        }

        // ── 3 · battery (UPower ETA + 1-hour spark line) ────────────────────
        Glass {
            Layout.preferredWidth: win.unit; Layout.preferredHeight: win.rowStd
            radius: Theme.radiusXl
            Caption { text: "Battery" }
            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                spacing: 6
                Row {
                    spacing: 8
                    Text {
                        text: Battery.present ? Math.round(Battery.pct * 100) + "%" : "AC"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 40; font.weight: Font.Bold
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: Battery.charging ? "bolt" : "battery"
                        level: Battery.pct; charging: Battery.charging
                        size: 22
                        color: Battery.charging ? Theme.green : Battery.pct < 0.2 ? Theme.red : Theme.text2
                    }
                }
                Canvas {
                    id: spark
                    width: parent.width; height: 30
                    property var pts: Battery.series
                    onPtsChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        if (!pts || pts.length < 2) return
                        const t0 = pts[0].t, span = Math.max(1, pts[pts.length - 1].t - t0)
                        const X = p => (p.t - t0) / span * width
                        const Y = p => height - 2 - p.p * (height - 4)
                        const col = Battery.charging ? Theme.green : Battery.pct < 0.2 ? Theme.red : Theme.accent
                        ctx.beginPath(); ctx.moveTo(X(pts[0]), Y(pts[0]))
                        for (let i = 1; i < pts.length; i++) ctx.lineTo(X(pts[i]), Y(pts[i]))
                        ctx.strokeStyle = col; ctx.lineWidth = 1.6; ctx.stroke()
                        ctx.lineTo(width, height); ctx.lineTo(0, height); ctx.closePath()
                        const g = ctx.createLinearGradient(0, 0, 0, height)
                        g.addColorStop(0, Theme.alpha(col, 0.35)); g.addColorStop(1, Theme.alpha(col, 0.0))
                        ctx.fillStyle = g; ctx.fill()
                    }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: (Battery.eta || (Battery.charging ? "charging" : Battery.present ? "on battery" : "plugged in"))
                          + (Battery.rateW > 0.1 ? "  ·  " + Battery.rateW.toFixed(1) + " W" : "")
                    color: Theme.muted
                    font.family: Theme.font; font.pixelSize: Theme.fontXs
                }
            }
        }

        // ── 4 · system meters ───────────────────────────────────────────────
        Glass {
            Layout.preferredWidth: win.unit; Layout.preferredHeight: win.rowStd
            radius: Theme.radiusXl
            Caption { text: "System" }
            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                spacing: 9
                Repeater {
                    model: [
                        { label: "CPU",  v: Sys.cpu, txt: Math.round(Sys.cpu) + "%",           col: Theme.accent },
                        { label: "RAM",  v: Sys.mem, txt: Sys.memUsedGb.toFixed(1) + "G",       col: Theme.green },
                        { label: "GPU",  v: Sys.gpu, txt: Sys.gpuAsleep ? "asleep" : Sys.vramUsedGb.toFixed(1) + "G", col: Theme.purple },
                        { label: "TEMP", v: Math.min(100, Sys.cpuTempC), txt: Sys.cpuTempC + "°", col: Theme.yellow },
                    ]
                    Row {
                        required property var modelData
                        width: parent.width
                        spacing: 8
                        Text {
                            width: 34
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: Theme.muted
                            font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.Bold
                        }
                        Rectangle {
                            width: parent.width - 34 - 44 - 16; height: 6; radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.alpha(Theme.text, 0.08)
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, modelData.v / 100))
                                height: parent.height; radius: parent.radius
                                color: modelData.col
                                Behavior on width { NumberAnimation { duration: 400 } }
                            }
                        }
                        Text {
                            width: 44
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: modelData.txt
                            color: Theme.text
                            font.family: Theme.fontMono; font.pixelSize: 11
                        }
                    }
                }
            }
        }

        // ── 5 · disk ────────────────────────────────────────────────────────
        Glass {
            Layout.preferredWidth: win.unit; Layout.preferredHeight: win.rowStd
            radius: Theme.radiusXl
            Caption { text: "Storage" }
            Item {
                anchors { fill: parent; topMargin: 34; margins: 16 }
                // ring gauge
                Canvas {
                    id: ring
                    width: 92; height: 92
                    anchors.verticalCenter: parent.verticalCenter
                    property real frac: Math.max(0, Math.min(1, Sys.diskUsedPct / 100))
                    onFracChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d"); ctx.reset()
                        const c = width / 2, r = c - 7
                        ctx.lineWidth = 9; ctx.lineCap = "round"
                        ctx.strokeStyle = Theme.alpha(Theme.text, 0.08)
                        ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.stroke()
                        ctx.strokeStyle = frac > 0.9 ? Theme.red : frac > 0.75 ? Theme.yellow : Theme.accent
                        ctx.beginPath(); ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2); ctx.stroke()
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Math.round(Sys.diskUsedPct) + "%"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.fontMd; font.weight: Font.Bold
                    }
                }
                Column {
                    anchors { left: ring.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text {
                        text: (Sys.diskTotalGb - Sys.diskUsedGb).toFixed(0) + " GB"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.fontLg; font.weight: Font.Bold
                    }
                    Text {
                        text: "free of " + Sys.diskTotalGb.toFixed(0) + " GB"
                        color: Theme.muted
                        font.family: Theme.font; font.pixelSize: Theme.fontXs
                    }
                }
            }
        }

        // ── 6 · weather (wttr.in via Weather service) ───────────────────────
        Glass {
            Layout.preferredWidth: win.unit; Layout.preferredHeight: win.rowStd
            radius: Theme.radiusXl
            Caption { text: Weather.place || "Weather" }
            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                spacing: 2
                Row {
                    spacing: 12
                    Icon {
                        name: Weather.icon
                        size: 36
                        color: Weather.icon === "sun" ? Theme.yellow : Weather.icon === "bolt" ? Theme.purple : Theme.text2
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: Weather.tempC || "—"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 40; font.weight: Font.Bold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: Weather.cond || (Weather.lastFetch === 0 ? "fetching…" : "offline")
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: Theme.fontSm
                }
            }
        }

        // ── 7 · media (MPRIS) ───────────────────────────────────────────────
        Glass {
            Layout.columnSpan: 2
            Layout.preferredWidth: win.wide; Layout.preferredHeight: win.rowStd
            radius: Theme.radiusXl
            Caption { text: win.player ? (win.player.identity || "Now playing") : "Media" }
            Row {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                spacing: 14

                Rectangle {
                    width: 84; height: 84; radius: Theme.radiusMd
                    color: Theme.alpha(Theme.text, 0.06)
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: win.player ? (win.player.trackArtUrl || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: !win.player || !win.player.trackArtUrl
                        name: "play"; size: 26; color: Theme.muted
                    }
                }

                Column {
                    width: parent.width - 84 - 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: win.player ? (win.player.trackTitle || "Untitled") : "Nothing playing"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.fontLg; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: win.player ? (win.player.trackArtist || "") : "Start something in any MPRIS player"
                        color: Theme.muted
                        font.family: Theme.font; font.pixelSize: Theme.fontSm
                    }
                    Row {
                        spacing: 18
                        visible: !!win.player
                        IconButton { icon: "prev"; iconSize: 18; onClicked: win.player?.previous() }
                        IconButton {
                            icon: win.player && win.player.isPlaying ? "pause" : "play"
                            iconSize: 22
                            onClicked: win.player?.togglePlaying()
                        }
                        IconButton { icon: "next"; iconSize: 18; onClicked: win.player?.next() }
                    }
                }
            }
        }

        // ── 8 · network ─────────────────────────────────────────────────────
        Glass {
            Layout.preferredWidth: win.unit; Layout.preferredHeight: win.rowStd
            radius: Theme.radiusXl
            Caption { text: "Network" }
            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                spacing: 4
                Icon {
                    name: Net.icon || "wifi-off"
                    size: 30
                    color: (Net.wired || Net.wifiConnected) ? Theme.accent : Theme.muted
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: Net.label || "Offline"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold
                }
                Text {
                    text: "↓ " + win.fmtRate(Sys.netDown) + "   ↑ " + win.fmtRate(Sys.netUp)
                    color: Theme.muted
                    font.family: Theme.fontMono; font.pixelSize: 10
                }
            }
        }

        // ── 9 · uptime ──────────────────────────────────────────────────────
        Glass {
            Layout.preferredWidth: win.unit; Layout.preferredHeight: win.rowStd
            radius: Theme.radiusXl
            Caption { text: "Uptime" }
            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                spacing: 4
                Text {
                    text: win.uptimeStr || "—"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 32; font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: win.kernel ? "Linux " + win.kernel : ""
                    color: Theme.muted
                    font.family: Theme.fontMono; font.pixelSize: 10
                }
            }
        }
    }
}
