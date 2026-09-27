import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import "root:/Config"
import "root:/Services"
import "root:/components"

// Full-screen widget board — iOS StandBy-style tiles laid out in a grid.
// Bound to Shell.overlay === "widgets" (SUPER+B in Hyprland).
// Tiles: BIG clock, calendar (month view with today highlighted), battery
// with %, CPU/RAM/GPU meters, disk, active MPRIS media player, and a
// weather placeholder that tries wttr.in via Quickshell.Io.
OverlayWindow {
    id: win
    name: "widgets"
    scrim: true

    // pull Sys stats while open
    Component.onCompleted: {}
    onOpenedChanged: if (open) Sys.active++
    Connections {
        target: win
        function onOpenChanged() { if (!win.open) Sys.active = Math.max(0, Sys.active - 1) }
    }

    SystemClock { id: sysClock; precision: SystemClock.Seconds }

    // ── layout ─────────────────────────────────────────────────────────────
    GridLayout {
        anchors.centerIn: parent
        columns: 4
        rowSpacing: 18
        columnSpacing: 18
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Theme.easePop } }
        Behavior on scale   { NumberAnimation { duration: Theme.normal; easing.type: Theme.easePop } }

        // ── 1. BIG CLOCK ────────────────────────────────────────────────
        Glass {
            Layout.preferredWidth: 380; Layout.preferredHeight: 220
            Layout.columnSpan: 2
            radius: Theme.radiusXl
            Column {
                anchors.centerIn: parent
                spacing: 4
                Text {
                    text: Qt.formatDateTime(sysClock.date, Settings.clock24h ? "HH:mm" : "h:mm AP")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 96; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: Qt.formatDateTime(sysClock.date, "dddd, d MMMM")
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: Theme.fontMd
                    horizontalAlignment: Text.AlignHCenter; anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // ── 2. CALENDAR — current month with today highlighted ─────────
        Glass {
            Layout.preferredWidth: 380; Layout.preferredHeight: 220
            Layout.columnSpan: 2
            radius: Theme.radiusXl
            Item {
                anchors.fill: parent
                anchors.margins: 14
                property date today: sysClock.date
                property int  y: today.getFullYear()
                property int  m: today.getMonth()
                property int  firstDow: new Date(y, m, 1).getDay()
                property int  daysInMonth: new Date(y, m + 1, 0).getDate()

                Row {
                    id: header
                    spacing: 6
                    anchors.top: parent.top
                    Text {
                        text: Qt.formatDateTime(parent.parent.today, "MMMM yyyy")
                        color: Theme.accent
                        font.family: Theme.font; font.pixelSize: Theme.fontMd; font.weight: Font.Bold
                    }
                }
                Grid {
                    anchors.top: header.bottom; anchors.topMargin: 8
                    columns: 7
                    columnSpacing: 4; rowSpacing: 3
                    // day-of-week headers
                    Repeater {
                        model: ["S","M","T","W","T","F","S"]
                        Rectangle {
                            width: 44; height: 18
                            color: "transparent"
                            Text { anchors.centerIn: parent; text: modelData; color: Theme.muted
                                   font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.Bold }
                        }
                    }
                    // blank days before day 1
                    Repeater {
                        model: parent.parent.firstDow
                        Item { width: 44; height: 22 }
                    }
                    // days
                    Repeater {
                        model: parent.parent.daysInMonth
                        Rectangle {
                            width: 44; height: 22
                            radius: 6
                            readonly property int day: index + 1
                            readonly property bool isToday: day === (new Date()).getDate()
                            color: isToday ? Theme.accent : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: day
                                color: parent.isToday ? Theme.onAccent : Theme.text
                                font.family: Theme.fontMono; font.pixelSize: 11
                                font.weight: parent.isToday ? Font.Bold : Font.Normal
                            }
                        }
                    }
                }
            }
        }

        // ── 3. BATTERY ──────────────────────────────────────────────────
        Glass {
            Layout.preferredWidth: 220; Layout.preferredHeight: 180
            radius: Theme.radiusXl
            readonly property var dev: UPower.displayDevice
            readonly property real pct: dev ? (dev.percentage > 1 ? dev.percentage / 100 : dev.percentage) : 1.0
            readonly property bool chg: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
            visible: dev && dev.isLaptopBattery
            Column {
                anchors.centerIn: parent
                spacing: 6
                Row {
                    spacing: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    Icon { name: parent.parent.parent.chg ? "battery" : "battery"; size: 22; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Battery"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; anchors.verticalCenter: parent.verticalCenter }
                }
                Text {
                    text: Math.round(parent.parent.pct * 100) + "%"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 48; font.weight: Font.Bold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Rectangle {
                    width: 160; height: 8; radius: 4; color: Theme.alpha(Theme.text, 0.08)
                    anchors.horizontalCenter: parent.horizontalCenter
                    Rectangle {
                        width: parent.width * parent.parent.parent.pct; height: parent.height; radius: parent.radius
                        color: parent.parent.parent.pct > 0.5 ? Theme.green : parent.parent.parent.pct > 0.2 ? Theme.yellow : Theme.red
                    }
                }
                Text {
                    text: parent.parent.chg ? "charging" : (parent.parent.dev ? "on battery" : "")
                    color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // ── 4. SYSTEM METERS — CPU / RAM / GPU / TEMP ───────────────────
        Glass {
            Layout.preferredWidth: 300; Layout.preferredHeight: 180
            radius: Theme.radiusXl
            Column {
                anchors.centerIn: parent
                spacing: 10
                width: 240
                Repeater {
                    model: [
                        { label: "CPU",  v: Sys.cpu,  txt: Math.round(Sys.cpu) + "%",           col: Theme.accent },
                        { label: "RAM",  v: Sys.mem,  txt: Sys.memUsedGb.toFixed(1) + "G",       col: Theme.green  },
                        { label: "GPU",  v: Sys.gpu,  txt: Sys.vramUsedGb.toFixed(1) + "G",      col: Theme.purple },
                        { label: "TEMP", v: Math.min(100, Sys.cpuTempC), txt: Sys.cpuTempC + "°", col: Theme.yellow },
                    ]
                    Row {
                        spacing: 10; width: parent.width
                        Text { text: modelData.label; color: Theme.muted; width: 40
                               font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.Bold
                               anchors.verticalCenter: parent.verticalCenter }
                        Rectangle {
                            width: 130; height: 6; radius: 3
                            color: Theme.alpha(Theme.text, 0.08)
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                width: parent.width * Math.min(1, modelData.v/100)
                                height: parent.height; radius: parent.radius
                                color: modelData.col
                                Behavior on width { NumberAnimation { duration: 400 } }
                            }
                        }
                        Text { text: modelData.txt; color: Theme.text; width: 44
                               font.family: Theme.fontMono; font.pixelSize: 11
                               anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }

        // ── 5. DISK ─────────────────────────────────────────────────────
        Glass {
            Layout.preferredWidth: 240; Layout.preferredHeight: 180
            radius: Theme.radiusXl
            property real usedPct: Sys.diskUsedPct || 0
            property real totalGb: Sys.diskTotalGb || 0
            property real usedGb: Sys.diskUsedGb || 0
            Column {
                anchors.centerIn: parent
                spacing: 8
                Row {
                    spacing: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    Icon { name: "storage"; size: 20; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Disk"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; anchors.verticalCenter: parent.verticalCenter }
                }
                Text {
                    text: parent.parent.usedGb.toFixed(1) + " / " + parent.parent.totalGb.toFixed(0) + " G"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontLg; font.weight: Font.Bold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: Math.round(parent.parent.usedPct) + "% used"
                    color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: 11
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // ── 6. MEDIA / MPRIS ────────────────────────────────────────────
        Glass {
            Layout.preferredWidth: 380; Layout.preferredHeight: 180
            Layout.columnSpan: 2
            radius: Theme.radiusXl
            readonly property var player: Mpris.players.values.length
                ? (Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0]) : null
            Column {
                anchors.centerIn: parent
                spacing: 8; width: 340
                Text {
                    text: parent.parent.player ? (parent.parent.player.trackTitle || "Untitled") : "Nothing playing"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontLg; font.weight: Font.DemiBold
                    elide: Text.ElideRight; width: parent.width; horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    text: parent.parent.player ? (parent.parent.player.trackArtist || parent.parent.player.identity || "") : ""
                    color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontSm
                    elide: Text.ElideRight; width: parent.width; horizontalAlignment: Text.AlignHCenter
                }
                Row {
                    spacing: 24
                    anchors.horizontalCenter: parent.horizontalCenter
                    IconButton { icon: "prev"; iconSize: 22; visible: !!parent.parent.parent.player
                                 onClicked: parent.parent.parent.player.previous() }
                    IconButton { icon: parent.parent.parent.player && parent.parent.parent.player.isPlaying ? "pause" : "play"
                                 iconSize: 28; visible: !!parent.parent.parent.player
                                 onClicked: parent.parent.parent.player.togglePlaying() }
                    IconButton { icon: "next"; iconSize: 22; visible: !!parent.parent.parent.player
                                 onClicked: parent.parent.parent.player.next() }
                }
            }
        }

        // ── 7. WEATHER (via wttr.in — free, no key) ─────────────────────
        Glass {
            Layout.preferredWidth: 240; Layout.preferredHeight: 180
            radius: Theme.radiusXl
            Component.onCompleted: Weather.active++
            Component.onDestruction: Weather.active = Math.max(0, Weather.active - 1)
            Column {
                anchors.centerIn: parent
                spacing: 4
                Text { text: "Weather"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs
                       anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: Weather.emoji || "🌤"; font.pixelSize: 32
                       anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: Weather.tempC || "—"; color: Theme.text
                       font.family: Theme.font; font.pixelSize: 34; font.weight: Font.Bold
                       anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: Weather.cond || (Weather.lastFetch === 0 ? "fetching…" : "offline")
                       color: Theme.text2
                       font.family: Theme.font; font.pixelSize: Theme.fontSm
                       anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: Weather.place; color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: 10
                       anchors.horizontalCenter: parent.horizontalCenter }
            }
        }
    }

    // Keep tile refreshes reasonable — 5 s tick for the weather fetcher etc.
    Timer { id: ticker; interval: 5000; running: win.open; repeat: true }
}
