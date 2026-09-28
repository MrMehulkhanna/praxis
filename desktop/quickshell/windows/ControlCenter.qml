import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import "root:/Config"
import "root:/Services"
import "root:/components"

// Control Center — every value here is live system state.
OverlayWindow {
    id: win
    name: "cc"
    scrim: false
    grabKeyboard: false
    onOpened: { Power.refreshProfile(); Power.refreshBrightness(); Aios.refresh() }

    readonly property var player: Mpris.players.values.length ? (Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0]) : null
    readonly property var bat: UPower.displayDevice
    readonly property real batPct: bat ? (bat.percentage > 1 ? bat.percentage / 100 : bat.percentage) : 1
    readonly property bool charging: bat && (bat.state === UPowerDeviceState.Charging || bat.state === UPowerDeviceState.FullyCharged)
    function fmtTime(s) { if (!s || s <= 0) return ""; const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60); return h ? `${h}h ${m}m` : `${m}m` }

    property string confirmAction: ""
    Timer { id: confirmReset; interval: 3000; onTriggered: win.confirmAction = "" }
    function power(action, fn) {
        if (confirmAction === action) { confirmAction = ""; fn(); Shell.closeAll(); return }
        confirmAction = action; confirmReset.restart()
    }

    Glass {
        id: card
        anchors { top: parent.top; right: parent.right; topMargin: Theme.barHeight + Theme.barMargin + 8; rightMargin: Theme.barMargin }
        width: 400
        height: col.implicitHeight + 32
        radius: Theme.radiusXl
        color: Theme.glassStrong
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        transformOrigin: Item.TopRight
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Theme.easePop; easing.overshoot: Theme.popOvershoot } }
        MouseArea { anchors.fill: parent }

        component Tile: Rectangle {
            property string icon: "wifi"
            property string title: ""
            property string subtitle: ""
            property bool on: false
            property bool showChevron: true
            signal toggled()
            signal more()
            width: (col.width - 10) / 2; height: 68
            radius: Theme.radiusLg
            color: on ? Theme.accent : Theme.alpha(Theme.text, 0.06)
            border.width: 1; border.color: on ? "transparent" : Theme.border
            Behavior on color { ColorAnimation { duration: Theme.normal } }
            Row {
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 10
                Rectangle {
                    width: 36; height: 36; radius: 18
                    color: parent.parent.on ? Theme.alpha(Theme.onAccent, 0.15) : Theme.alpha(Theme.text, 0.08)
                    anchors.verticalCenter: parent.verticalCenter
                    Icon { anchors.centerIn: parent; name: parent.parent.parent.icon; size: 18; color: parent.parent.parent.on ? Theme.onAccent : Theme.text }
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: parent.parent.parent.toggled() }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text { text: parent.parent.parent.title; color: parent.parent.parent.on ? Theme.onAccent : Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
                    Text { text: parent.parent.parent.subtitle; color: parent.parent.parent.on ? Theme.alpha(Theme.onAccent, 0.75) : Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; width: 110 }
                }
            }
            Icon {
                visible: parent.showChevron
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                name: "chevron-right"; size: 14; color: parent.on ? Theme.alpha(Theme.onAccent, 0.7) : Theme.muted
            }
            MouseArea { anchors.fill: parent; z: -1; onClicked: parent.more() }
        }

        component Pill: Rectangle {
            property string icon: "moon"
            property string label: ""
            property bool on: false
            property color onColor: Theme.accent
            signal clicked()
            height: 34; width: pr.width + 22; radius: 17
            color: on ? onColor : pma.containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.06)
            border.width: 1; border.color: on ? "transparent" : Theme.border
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            Row {
                id: pr; anchors.centerIn: parent; spacing: 6
                Icon { name: parent.parent.icon; size: 14; color: parent.parent.on ? Theme.onAccent : Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                Text { text: parent.parent.label; color: parent.parent.on ? Theme.onAccent : Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicked() }
        }

        Column {
            id: col
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
            spacing: 10

            // ── connectivity tiles ──
            Row {
                spacing: 10
                Tile {
                    icon: Net.icon; title: Net.wired ? "Ethernet" : "Wi-Fi"; subtitle: Net.label
                    on: Net.wired || (Net.wifiEnabled && Net.wifiConnected)
                    onToggled: Net.setWifi(!Net.wifiEnabled)
                    onMore: { Shell.open("settings"); Shell.settingsSection = "Network" }
                }
                Tile {
                    icon: "bluetooth"; title: "Bluetooth"; subtitle: Net.btLabel
                    on: Net.btEnabled
                    onToggled: Net.setBt(!Net.btEnabled)
                    onMore: { Shell.open("settings"); Shell.settingsSection = "Bluetooth" }
                }
            }

            // ── quick pills ──
            Flow {
                width: parent.width; spacing: 8
                Pill { icon: Notifs.dnd ? "bell-off" : "moon"; label: "Do Not Disturb"; on: Notifs.dnd; onClicked: Notifs.toggleDnd() }
                Pill {
                    icon: Power.profile === "performance" ? "bolt" : Power.profile === "power-saver" ? "leaf" : "gauge"
                    label: Power.profile === "performance" ? "Performance" : Power.profile === "power-saver" ? "Power saver" : "Balanced"
                    on: Power.profile === "performance"; onColor: Theme.purple
                    onClicked: Power.setProfile(Power.profiles[(Power.profiles.indexOf(Power.profile) + 1) % Power.profiles.length])
                }
                Pill {
                    icon: "layers"; label: Settings.profile; on: Settings.profile !== "Normal"; onColor: Theme.accent
                    onClicked: { const p = ["Normal", "Development", "Cyber Lab", "Presentation"]; Settings.profile = p[(p.indexOf(Settings.profile) + 1) % p.length] }
                }
                Pill { icon: EyeComfort.enabled ? "eye-off" : "eye"; label: "Eye Comfort"; on: EyeComfort.enabled; onClicked: EyeComfort.toggle() }
                Pill { icon: "lock"; label: "Lock"; onClicked: { Power.lock(); Shell.closeAll() } }
            }

            // ── sliders ──
            Rectangle {
                width: parent.width; height: sl.implicitHeight + 20; radius: Theme.radiusLg
                color: Theme.alpha(Theme.text, 0.05); border.width: 1; border.color: Theme.border
                Column {
                    id: sl
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 2
                    Slider {
                        // full travel = 10–100 % (see Power.minBrightness)
                        width: parent.width; icon: "sun"
                        value: (Power.brightness - Power.minBrightness) / (1 - Power.minBrightness)
                        valueText: Math.round((Power.minBrightness + (1 - Power.minBrightness) * shown) * 100) + "%"
                        onMoved: v => Power.setBrightness(Power.minBrightness + (1 - Power.minBrightness) * v)
                    }
                    Slider {
                        width: parent.width; icon: Audio.icon
                        value: Audio.muted ? 0 : Audio.volume
                        fillColor: Audio.muted ? Theme.muted : Theme.accent
                        onMoved: v => Audio.setVolume(v)
                        onIconClicked: Audio.toggleMute()
                    }
                    Slider {
                        width: parent.width; icon: "mic"
                        value: Audio.micMuted ? 0 : Audio.micVolume
                        fillColor: Audio.micMuted ? Theme.muted : Theme.green
                        onMoved: v => Audio.setMicVolume(v)
                        onIconClicked: Audio.toggleMicMute()
                    }
                    Slider {
                        width: parent.width; icon: EyeComfort.enabled ? "eye-off" : "eye"
                        value: EyeComfort.intensity
                        fillColor: EyeComfort.enabled ? Theme.yellow : Theme.muted
                        onMoved: v => EyeComfort.intensity = v
                        onIconClicked: EyeComfort.toggle()
                    }
                    Text {
                        text: Audio.sinkName
                        color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs
                        elide: Text.ElideRight; width: parent.width; leftPadding: 28
                    }
                }
            }

            // ── media ──
            Rectangle {
                visible: !!win.player
                width: parent.width; height: 74; radius: Theme.radiusLg
                color: Theme.alpha(Theme.text, 0.05); border.width: 1; border.color: Theme.border
                Row {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 12
                    Rectangle {
                        width: 54; height: 54; radius: Theme.radiusMd; color: Theme.surface3; clip: true
                        anchors.verticalCenter: parent.verticalCenter
                        Image { anchors.fill: parent; source: win.player ? win.player.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                        Icon { anchors.centerIn: parent; name: "play"; size: 20; color: Theme.muted; visible: !win.player || !win.player.trackArtUrl }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        width: card.width - 32 - 54 - 12 - 12 - 120
                        Text { text: win.player ? (win.player.trackTitle || "Nothing playing") : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; elide: Text.ElideRight; width: parent.width }
                        Text { text: win.player ? (win.player.trackArtist || win.player.identity) : ""; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; width: parent.width }
                    }
                }
                Row {
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    IconButton { icon: "prev"; iconSize: 14; onClicked: win.player.previous(); anchors.verticalCenter: parent.verticalCenter }
                    IconButton {
                        icon: win.player && win.player.isPlaying ? "pause" : "play"; iconSize: 16
                        active: true; implicitWidth: 36; implicitHeight: 36; radius: 18
                        onClicked: win.player.togglePlaying(); anchors.verticalCenter: parent.verticalCenter
                    }
                    IconButton { icon: "next"; iconSize: 14; onClicked: win.player.next(); anchors.verticalCenter: parent.verticalCenter }
                }
            }

            // ── battery + AI status ──
            Row {
                spacing: 10
                Rectangle {
                    visible: win.bat && win.bat.isLaptopBattery
                    width: (col.width - 10) / 2; height: 56; radius: Theme.radiusLg
                    color: Theme.alpha(Theme.text, 0.05); border.width: 1; border.color: Theme.border
                    Row {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Icon { name: "battery"; size: 22; level: win.batPct; charging: win.charging; color: win.batPct <= 0.15 && !win.charging ? Theme.red : win.charging ? Theme.green : Theme.text; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: Math.round(win.batPct * 100) + "%"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontLg; font.weight: Font.Bold }
                            Text {
                                text: win.charging ? (win.bat.timeToFull > 0 ? win.fmtTime(win.bat.timeToFull) + " to full" : "Charging") : (win.bat && win.bat.timeToEmpty > 0 ? win.fmtTime(win.bat.timeToEmpty) + " left" : "On battery")
                                color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs
                            }
                        }
                    }
                }
                Rectangle {
                    width: (col.width - 10) / 2; height: 56; radius: Theme.radiusLg
                    color: aiMa.containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.05); border.width: 1; border.color: Theme.border
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Row {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Icon { name: "sparkle"; size: 20; color: Aios.online ? Theme.accent : Theme.muted; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: Aios.selectedInfo ? Aios.selectedInfo.label : "AIOS"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
                            Text { text: !Aios.online ? "offline" : Aios.loadedModel ? "loaded · " + Aios.budgetMode : "idle · " + Aios.budgetMode; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs }
                        }
                    }
                    MouseArea { id: aiMa; anchors.fill: parent; hoverEnabled: true; onClicked: Shell.open("ai") }
                }
            }

            // ── power row ──
            Row {
                width: parent.width
                spacing: 6
                Repeater {
                    model: [
                        { id: "suspend",  icon: "moon",    label: "Sleep",   fn: () => Power.suspend() },
                        { id: "logout",   icon: "user",    label: "Log out", fn: () => Power.logout() },
                        { id: "reboot",   icon: "refresh", label: "Restart", fn: () => Power.reboot() },
                        { id: "poweroff", icon: "power",   label: "Off",     fn: () => Power.poweroff() },
                    ]
                    Rectangle {
                        required property var modelData
                        readonly property bool arming: win.confirmAction === modelData.id
                        width: (col.width - 18) / 4; height: 40; radius: Theme.radiusMd
                        color: arming ? Theme.red : pwMa.containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.05)
                        border.width: 1; border.color: arming ? "transparent" : Theme.border
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                        Row {
                            anchors.centerIn: parent; spacing: 6
                            Icon { name: modelData.icon; size: 14; color: arming ? Theme.bg : Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: arming ? "Sure?" : modelData.label; color: arming ? Theme.bg : Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: pwMa; anchors.fill: parent; hoverEnabled: true; onClicked: win.power(modelData.id, modelData.fn) }
                    }
                }
            }

            // ── footer ──
            Row {
                width: parent.width
                Text { text: "Settings"; color: Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontXs; anchors.verticalCenter: parent.verticalCenter; visible: false }
                Item { width: parent.width - gearBtn.width; height: 1 }
                IconButton { id: gearBtn; icon: "gear"; label: "Settings"; onClicked: { Shell.closeAll(); Shell.open("settings") } }
            }
        }
    }
}
