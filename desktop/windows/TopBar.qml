import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "root:/Config"
import "root:/Services"
import "root:/components"

// One bar per monitor. Left: workspaces + focused window. Centre: clock.
// Right: live system status and the entry points to every panel.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barHeight + Theme.barMargin
    exclusiveZone: Theme.barHeight + Theme.barMargin
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell"

    readonly property var hyprMon: Hyprland.monitorFor(screen)
    readonly property bool isFocusedScreen: Hyprland.focusedMonitor && hyprMon && Hyprland.focusedMonitor.name === hyprMon.name

    Glass {
        anchors { fill: parent; leftMargin: Theme.barMargin; rightMargin: Theme.barMargin; topMargin: Theme.barMargin; bottomMargin: 0 }
        radius: Theme.radiusMd
        shadowStrength: 0.6

        // ── LEFT ────────────────────────────────────────────────────────
        Row {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 10

            // workspaces on this monitor
            Row {
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: ScriptModel {
                        values: Hyprland.workspaces.values
                            .filter(w => w.id > 0 && (!bar.hyprMon || (w.monitor && w.monitor.name === bar.hyprMon.name)))
                            .sort((a, b) => a.id - b.id)
                    }
                    Rectangle {
                        required property var modelData
                        readonly property bool isActive: modelData.active
                        width: isActive ? 30 : 22; height: 22
                        radius: 11
                        color: isActive ? Theme.accent : wsMa.containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.06)
                        border.width: 1
                        border.color: isActive ? "transparent" : modelData.urgent ? Theme.red : Theme.border
                        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Theme.easePop; easing.overshoot: Theme.popOvershoot } }
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.name.length <= 2 ? modelData.name : modelData.id
                            color: parent.isActive ? Theme.onAccent : Theme.text2
                            font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.Bold
                        }
                        MouseArea { id: wsMa; anchors.fill: parent; hoverEnabled: true; onClicked: HyprOpts.dispatch(`hl.dsp.focus({ workspace = ${modelData.id} })`) }
                    }
                }
                // "+" new workspace
                Rectangle {
                    width: 22; height: 22; radius: 11
                    color: plusMa.containsMouse ? Theme.hover : "transparent"
                    anchors.verticalCenter: parent.verticalCenter
                    Icon { anchors.centerIn: parent; name: "plus"; size: 12; color: Theme.muted }
                    MouseArea { id: plusMa; anchors.fill: parent; hoverEnabled: true; onClicked: HyprOpts.dispatch('hl.dsp.focus({ workspace = "empty" })') }
                }
            }

            Rectangle { width: 1; height: 16; color: Theme.border; anchors.verticalCenter: parent.verticalCenter }

            // focused window title
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: bar.isFocusedScreen
                text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : "Desktop"
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.Medium
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 320)
            }
        }

        // ── CENTRE: clock ────────────────────────────────────────────────
        SystemClock { id: clock; precision: Settings.showSeconds ? SystemClock.Seconds : SystemClock.Minutes }
        Rectangle {
            anchors.centerIn: parent
            width: clockRow.width + 20; height: 26; radius: 13
            color: clockMa.containsMouse ? Theme.hover : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            Row {
                id: clockRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    text: Qt.formatDateTime(clock.date, "ddd d MMM")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: Qt.formatDateTime(clock.date, Settings.clock24h ? (Settings.showSeconds ? "HH:mm:ss" : "HH:mm") : (Settings.showSeconds ? "h:mm:ss AP" : "h:mm AP"))
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontMd; font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea { id: clockMa; anchors.fill: parent; hoverEnabled: true; onClicked: Notifs.togglePanel() }
        }

        // ── RIGHT ────────────────────────────────────────────────────────
        Row {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 2

            // system stats (profile-dependent)
            Row {
                id: stats
                visible: Settings.statsVisible
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                rightPadding: 8
                Component.onCompleted: Sys.active++
                Component.onDestruction: Sys.active--
                onVisibleChanged: Sys.active += visible ? 1 : -1
                Repeater {
                    model: [
                        { icon: "cpu", v: Sys.cpu, txt: Math.round(Sys.cpu) + "%" },
                        { icon: "memory", v: Sys.mem, txt: Sys.memUsedGb.toFixed(1) + "G" },
                        { icon: "gpu", v: Sys.gpu, txt: Sys.vramUsedGb.toFixed(1) + "G" },
                        { icon: "sun", v: Sys.cpuTempC, txt: Sys.cpuTempC + "°" },
                    ]
                    Row {
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Icon { name: modelData.icon; size: 13; color: modelData.v > 85 ? Theme.red : modelData.v > 60 ? Theme.yellow : Theme.muted; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.txt; color: Theme.text2; font.family: Theme.fontMono; font.pixelSize: Theme.fontXs; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }

            VoiceButton { anchors.verticalCenter: parent.verticalCenter }

            IconButton {
                icon: Net.icon; iconSize: 15
                iconColor: Net.wired || Net.wifiConnected ? Theme.text : Theme.muted
                anchors.verticalCenter: parent.verticalCenter
                onClicked: Shell.toggle("cc")
            }
            IconButton {
                visible: Net.btAvailable && Net.btEnabled
                icon: "bluetooth"; iconSize: 15
                iconColor: Net.btConnected.length ? Theme.accent : Theme.text2
                anchors.verticalCenter: parent.verticalCenter
                onClicked: Shell.toggle("cc")
            }
            IconButton {
                icon: Audio.icon; iconSize: 15
                iconColor: Audio.muted ? Theme.muted : Theme.text
                anchors.verticalCenter: parent.verticalCenter
                onClicked: Shell.toggle("cc")
                onRightClicked: Audio.toggleMute()
                MouseArea {
                    anchors.fill: parent; acceptedButtons: Qt.NoButton
                    onWheel: wheel => Audio.step(wheel.angleDelta.y > 0 ? 0.05 : -0.05)
                }
            }
            IconButton {
                icon: EyeComfort.enabled ? "moon-filled" : "moon"; iconSize: 15
                iconColor: EyeComfort.enabled ? Theme.accent : Theme.text
                anchors.verticalCenter: parent.verticalCenter
                onClicked: EyeComfort.toggle()
                label: EyeComfort.enabled ? "Night Light" : ""
            }
            IconButton {
                readonly property var dev: UPower.displayDevice
                readonly property real pct: dev ? (dev.percentage > 1 ? dev.percentage / 100 : dev.percentage) : 1
                readonly property bool chg: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
                visible: dev && dev.isLaptopBattery
                icon: "battery"; iconSize: 17; level: pct; charging: chg
                iconColor: pct <= 0.15 && !chg ? Theme.red : chg ? Theme.green : Theme.text
                label: Math.round(pct * 100) + "%"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: Shell.toggle("cc")
            }
            IconButton {
                icon: Notifs.dnd ? "bell-off" : "bell"; iconSize: 15
                badge: Notifs.count > 0 && !Notifs.dnd
                active: Notifs.panelVisible
                anchors.verticalCenter: parent.verticalCenter
                onClicked: Notifs.togglePanel()
                onRightClicked: Notifs.toggleDnd()
            }

            // hairline: separates passive status readouts from interactive panels
            Rectangle {
                width: 1; height: 14; radius: 0.5
                color: Theme.borderStrong
                anchors.verticalCenter: parent.verticalCenter
                Item { width: 4; height: 1 }
            }

            // AI status chip: model · LOCAL/CLOUD · spinner while a job runs
            Rectangle {
                id: aiChip
                readonly property bool busy: Aios.jobs.length > 0 || Aios.streaming
                readonly property bool cloud: (Aios.lastRoute.mode || "LOCAL") === "CLOUD"
                height: 26; width: aiRow.width + 18; radius: 13
                anchors.verticalCenter: parent.verticalCenter
                color: Shell.overlay === "ai" ? Theme.accent : aiMa.containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.06)
                border.width: 1; border.color: Shell.overlay === "ai" ? "transparent" : Theme.border
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Row {
                    id: aiRow; anchors.centerIn: parent; spacing: 6
                    Icon {
                        name: aiChip.busy ? "refresh" : "sparkle"; size: 13
                        color: Shell.overlay === "ai" ? Theme.onAccent : !Aios.online ? Theme.muted : Theme.accent
                        anchors.verticalCenter: parent.verticalCenter
                        RotationAnimation on rotation { running: aiChip.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 1000 }
                        onRotationChanged: if (!aiChip.busy && rotation !== 0) rotation = 0
                    }
                    Text {
                        text: !Aios.online ? "offline" : (Aios.loadedInfo ? Aios.loadedInfo.label : Aios.selectedLabel)
                        color: Shell.overlay === "ai" ? Theme.onAccent : Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        visible: Aios.online
                        height: 14; width: bt.width + 8; radius: 7
                        color: aiChip.cloud ? Theme.alpha(Theme.purple, 0.25) : Theme.alpha(Theme.green, 0.2)
                        anchors.verticalCenter: parent.verticalCenter
                        Text { id: bt; anchors.centerIn: parent; text: aiChip.cloud ? "CLOUD" : Aios.loadedModel ? "LOCAL" : "IDLE"; color: aiChip.cloud ? Theme.purple : Aios.loadedModel ? Theme.green : Theme.muted; font.family: Theme.fontMono; font.pixelSize: 9; font.weight: Font.Bold }
                    }
                }
                MouseArea {
                    id: aiMa; anchors.fill: parent; hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => { if (mouse.button === Qt.RightButton) Shell.toggle("activity"); else Shell.toggle("ai") }
                }
            }
            IconButton {
                icon: "pulse"; iconSize: 16
                active: Shell.overlay === "activity"
                badge: Aios.jobs.length > 0
                anchors.verticalCenter: parent.verticalCenter
                onClicked: Shell.toggle("activity")
            }
            IconButton {
                icon: "search"; iconSize: 15
                anchors.verticalCenter: parent.verticalCenter
                onClicked: Shell.toggle("launcher")
            }
            IconButton {
                icon: "monitor"; iconSize: 15
                anchors.verticalCenter: parent.verticalCenter
                onClicked: Quickshell.execDetached(["xdg-open", "http://localhost:8501"])
            }
            IconButton {
                icon: "sliders"; iconSize: 15
                active: Shell.overlay === "cc"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: Shell.toggle("cc")
            }
        }
    }
}
