import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "root:/Config"
import "root:/Services"
import "root:/components"

// Settings — sidebar of sections, each one a live view of real state.
OverlayWindow {
    id: win
    name: "settings"
    onOpened: { HyprOpts.refresh(); Power.refreshProfile(); Wallpaper.refresh(); Aios.refreshWanted++; Aios.refresh(); sysinfo.running = true; binds.running = true }
    onOpenChanged: if (!open) { Aios.refreshWanted = Math.max(0, Aios.refreshWanted - 1); Net.stopScan(); Net.setDiscovering(false); win.wifiPskFor = "" }

    property string wifiPskFor: ""
    readonly property var sections: [
        { id: "General",     icon: "info" },
        { id: "Appearance",  icon: "eye" },
        { id: "Dock",        icon: "dock" },
        { id: "Display",     icon: "monitor" },
        { id: "Windows",     icon: "layers" },
        { id: "Keyboard",    icon: "keyboard" },
        { id: "Network",     icon: "wifi" },
        { id: "Bluetooth",   icon: "bluetooth" },
        { id: "Audio",       icon: "volume-high" },
        { id: "Power",       icon: "bolt" },
        { id: "Wallpaper",   icon: "image" },
        { id: "Profiles",    icon: "user" },
        { id: "AI",          icon: "sparkle" },
    ]

    // ── hardware snapshot (Power) ──
    property var hw: ({})
    Process {
        id: hwProbe
        command: ["curl", "-sf", "-m", "3", Aios.base + "/api/hardware"]
        stdout: StdioCollector { onStreamFinished: { try { win.hw = JSON.parse(this.text) } catch (e) {} } }
    }
    Timer { interval: 4000; running: win.open && Shell.settingsSection === "Power"; repeat: true; triggeredOnStart: true; onTriggered: if (!hwProbe.running) hwProbe.running = true }
    function hwSet(what, value) {
        hwSetProc.command = ["curl", "-sf", "-m", "150", "-X", "POST", Aios.base + "/api/hardware/set", "-H", "Content-Type: application/json",
                             "-d", JSON.stringify({ what, value })]
        hwSetProc.running = true
    }
    Process { id: hwSetProc; stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(this.text); if (!r.ok) Notifs.notify("Hardware", r.message) } catch (e) {} hwProbe.running = true } } }

    // ── system info (General) ──
    property var sysInfo: ({})
    Process {
        id: sysinfo
        command: ["bash", "-c", "echo \"host=$(cat /etc/hostname 2>/dev/null || hostnamectl hostname)\"; echo \"kernel=$(uname -r)\"; echo \"cpu=$(lscpu | sed -n 's/^Model name: *//p')\"; g=''; for d in /sys/bus/pci/devices/*; do [ \"$(cat $d/vendor)\" = 0x10de ] && case $(cat $d/class) in 0x03*) g=$d; break;; esac; done; if [ -n \"$g\" ] && [ \"$(cat $g/power/runtime_status)\" = suspended ]; then echo \"gpu=NVIDIA GPU (asleep)\"; else echo \"gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)\"; fi; echo \"ram=$(free -g | awk '/Mem:/{print $2}') GB\"; echo \"uptime=$(uptime -p | sed 's/up //')\"; echo \"qs=$(quickshell --version 2>/dev/null | head -1)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {}
                for (const l of this.text.trim().split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1) }
                win.sysInfo = o
            }
        }
    }
    // ── keybinds (Keyboard) ──
    property var bindList: []
    Process {
        id: binds
        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const mods = m => { const n = []; if (m & 64) n.push("Super"); if (m & 1) n.push("Shift"); if (m & 4) n.push("Ctrl"); if (m & 8) n.push("Alt"); return n }
                    win.bindList = JSON.parse(this.text).filter(b => b.key).map(b => ({ keys: mods(b.modmask).concat([b.key.toUpperCase()]).join(" + "), action: (b.dispatcher + " " + (b.arg || "")).trim() }))
                } catch (e) { win.bindList = [] }
            }
        }
    }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(980, parent.width - 60)
        height: Math.min(680, parent.height - 60)
        radius: Theme.radiusXl
        color: Theme.glassStrong
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Theme.easePop; easing.overshoot: Theme.popOvershoot } }
        MouseArea { anchors.fill: parent }

        // ── sidebar ──
        Item {
            id: sidebar
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: 220
            Rectangle { anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                width: 1; color: Theme.border }
            Column {
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                spacing: 2
                Text { text: "Settings"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontTitle; font.weight: Font.Bold; leftPadding: 8; bottomPadding: 10 }
                Repeater {
                    model: win.sections
                    Rectangle {
                        required property var modelData
                        readonly property bool on: Shell.settingsSection === modelData.id
                        width: parent.width; height: 34; radius: Theme.radiusMd
                        color: on ? Theme.alpha(Theme.accent, 0.2) : sma.containsMouse ? Theme.hover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                        Row {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            Icon { name: modelData.icon; size: 15; color: parent.parent.on ? Theme.accent : Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.id; color: parent.parent.on ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontMd; font.weight: parent.parent.on ? Font.DemiBold : Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; onClicked: Shell.settingsSection = modelData.id }
                    }
                }
            }
            IconButton { icon: "x"; label: "Close"; anchors { left: parent.left; bottom: parent.bottom; margins: 14 }
                onClicked: Shell.closeAll() }
        }

        // ── content ──
        Flickable {
            id: flick
            anchors { top: parent.top; bottom: parent.bottom; left: sidebar.right; right: parent.right; margins: 26 }
            contentHeight: content.implicitHeight + 20
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: content
                width: flick.width
                spacing: 6
                Text { text: Shell.settingsSection; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontTitle; font.weight: Font.Bold; bottomPadding: 10 }
                Loader {
                    width: parent.width
                    sourceComponent: {
                        switch (Shell.settingsSection) {
                            case "General": return general; case "Appearance": return appearance; case "Dock": return dockSec
                            case "Display": return display; case "Windows": return windowsSec; case "Keyboard": return keyboard
                            case "Network": return network; case "Bluetooth": return bluetooth; case "Audio": return audio
                            case "Power": return powerSec; case "Wallpaper": return wallpaper; case "Profiles": return profiles
                            case "AI": return ai; default: return general
                        }
                    }
                }
            }
        }
    }

    component H: Text { color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; topPadding: 14; bottomPadding: 4 }
    component Swatch: Rectangle {
        property color c: Theme.blue
        property bool on: false
        width: 28; height: 28; radius: 14; color: c
        border.width: on ? 3 : 1; border.color: on ? Theme.text : Theme.alpha(Theme.text, 0.2)
        signal clicked()
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }
    component Btn: IconButton { implicitHeight: 30; padding: 10 }
    component Card: Rectangle { width: parent.width; radius: Theme.radiusLg; color: Theme.alpha(Theme.text, 0.04); border.width: 1; border.color: Theme.border }

    // ═══════════════ GENERAL ═══════════════
    Component {
        id: general
        Column {
            spacing: 0
            Card {
                height: infoCol.implicitHeight + 24
                Column {
                    id: infoCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 4
                    Repeater {
                        model: [["Host", win.sysInfo.host], ["Kernel", win.sysInfo.kernel], ["CPU", win.sysInfo.cpu], ["GPU", win.sysInfo.gpu],
                                ["Memory", win.sysInfo.ram], ["Hyprland", HyprOpts.hyprVersion], ["Quickshell", win.sysInfo.qs], ["Uptime", win.sysInfo.uptime]]
                        Row {
                            spacing: 10
                            Text { text: modelData[0]; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontSm; width: 90 }
                            Text { text: modelData[1] || "…"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; elide: Text.ElideRight; width: infoCol.width - 100 }
                        }
                    }
                }
            }
            H { text: "CLOCK" }
            SettingRow { label: "24-hour clock"; Toggle { checked: Settings.clock24h; onToggled: v => Settings.clock24h = v } }
            SettingRow { label: "Show seconds"; Toggle { checked: Settings.showSeconds; onToggled: v => Settings.showSeconds = v } }
            H { text: "AI BACKEND" }
            SettingRow { label: "AIOS service"; description: Aios.online ? "Running · " + Aios.memoryObjects + " memory objects · " + Aios.runs + " runs logged" : "Not reachable on 127.0.0.1:8778"
                Row { spacing: 6
                    Btn { icon: "refresh"; label: "Restart"; onClicked: { Shell.run("systemctl --user restart aios.service"); Aios.refresh() } }
                    Btn { icon: "arrow"; label: "Open in browser"; onClicked: Shell.run("google-chrome-stable --app=http://127.0.0.1:8778 --class=aios") }
                }
            }
        }
    }

    // ═══════════════ APPEARANCE ═══════════════
    Component {
        id: appearance
        Column {
            spacing: 0
            H { text: "ACCENT" }
            SettingRow {
                label: "Accent colour"; description: "Auto follows the active profile"
                Row {
                    spacing: 8
                    Rectangle {
                        width: 28; height: 28; radius: 14; color: Theme.surface3
                        border.width: Settings.accent === "auto" ? 3 : 1; border.color: Settings.accent === "auto" ? Theme.text : Theme.alpha(Theme.text, 0.2)
                        Text { anchors.centerIn: parent; text: "A"; color: Theme.text; font.pixelSize: 12; font.weight: Font.Bold }
                        MouseArea { anchors.fill: parent; onClicked: Settings.accent = "auto" }
                    }
                    Repeater {
                        model: [Theme.blue, Theme.purple, Theme.green, Theme.teal, Theme.yellow, Theme.red]
                        Swatch { c: modelData; on: Settings.accent === String(modelData); onClicked: Settings.accent = String(modelData) }
                    }
                }
            }
            H { text: "GLASS" }
            SettingRow { label: "Transparency"; description: Math.round((1 - Settings.transparency) * 100) + "% see-through"
                Slider { width: 220; icon: "layers"; value: Settings.transparency; valueText: ""; onMoved: v => Settings.transparency = Math.max(0.2, Math.min(1, v)) } }
            SettingRow { label: "Background blur"; description: "Hyprland decoration:blur"
                Toggle { checked: HyprOpts.blur; onToggled: v => { HyprOpts.set("decoration:blur:enabled", v ? 1 : 0); Settings.blur = v } } }
            SettingRow { label: "Panel corner radius"; description: Settings.radius + " px"
                Slider { width: 220; icon: "layers"; value: (Settings.radius - 6) / 20; valueText: ""; onMoved: v => Settings.radius = Math.round(6 + v * 20) } }
            H { text: "MOTION" }
            SettingRow { label: "Animation intensity"
                Segmented { options: [{ value: 0, label: "Off" }, { value: 0.7, label: "Snappy" }, { value: 1, label: "Normal" }, { value: 1.5, label: "Slow" }]; value: Settings.animations; onSelected: v => Settings.animations = v } }
            SettingRow { label: "Window animations"; description: "Hyprland animations:enabled"
                Toggle { checked: HyprOpts.animations; onToggled: v => HyprOpts.set("animations:enabled", v ? 1 : 0) } }
            SettingRow { label: "Ambient glow"; description: "Soft light behind windows that follows the time of day. Pauses on battery and under fullscreen apps."
                Toggle { checked: Settings.ambientEnabled; onToggled: v => Settings.ambientEnabled = v } }
        }
    }

    // ═══════════════ DOCK ═══════════════
    Component {
        id: dockSec
        Column {
            spacing: 0
            SettingRow { label: "Icon size"; description: Settings.dockIconSize + " px"
                Slider { width: 220; icon: "dock"; value: (Settings.dockIconSize - 32) / 40; valueText: ""; onMoved: v => Settings.dockIconSize = Math.round(32 + v * 40) } }
            SettingRow { label: "Auto-hide"; description: "Reveal by moving the mouse to the bottom edge"
                Toggle { checked: Settings.dockAutoHide; onToggled: v => Settings.dockAutoHide = v } }
            SettingRow { label: "Hide over fullscreen apps"; description: "Get the dock out of the way of videos and games"
                Toggle { checked: Settings.dockHideOnFullscreen; onToggled: v => Settings.dockHideOnFullscreen = v } }
            SettingRow { label: "Show on every monitor"
                Toggle { checked: Settings.dockAllScreens; onToggled: v => Settings.dockAllScreens = v } }
            H { text: "PINNED APPS  —  right-click any dock icon to pin / unpin" }
            Flow {
                width: parent.width; spacing: 6
                Repeater {
                    model: Settings.dockFavorites
                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property var entry: DesktopEntries.byId(modelData) || DesktopEntries.heuristicLookup(modelData)
                        height: 32; width: fr.width + 20; radius: 16
                        color: Theme.alpha(Theme.text, 0.06); border.width: 1; border.color: Theme.border
                        Row {
                            id: fr; anchors.centerIn: parent; spacing: 6
                            Image { width: 16; height: 16; source: entry ? Quickshell.iconPath(entry.icon, true) : ""; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: entry ? entry.name : modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; anchors.verticalCenter: parent.verticalCenter }
                            Icon { name: "x"; size: 12; color: Theme.muted; anchors.verticalCenter: parent.verticalCenter
                                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { const f = Settings.dockFavorites.slice(); f.splice(index, 1); Settings.dockFavorites = f } } }
                        }
                    }
                }
            }
            H { text: "ADD APP" }
            Rectangle {
                width: parent.width; height: 36; radius: 18
                color: Theme.alpha(Theme.text, 0.06); border.width: 1; border.color: addInput.activeFocus ? Theme.alpha(Theme.accent, 0.6) : Theme.border
                TextInput { id: addInput; anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: TextInput.AlignVCenter; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; clip: true
                    Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: !addInput.text; text: "Type an app name…"; color: Theme.muted; font: addInput.font } }
            }
            Flow {
                width: parent.width; spacing: 6; topPadding: 6
                Repeater {
                    model: addInput.text.length < 2 ? [] : DesktopEntries.applications.values.filter(e => !e.noDisplay && e.name.toLowerCase().includes(addInput.text.toLowerCase()) && Settings.dockFavorites.indexOf(e.id) < 0).slice(0, 8)
                    Btn { required property var modelData; icon: "plus"; label: modelData.name; onClicked: { const f = Settings.dockFavorites.slice(); f.push(modelData.id); Settings.dockFavorites = f; addInput.text = "" } }
                }
            }
        }
    }

    // ═══════════════ DISPLAY ═══════════════
    Component {
        id: display
        Column {
            spacing: 10
            Component.onCompleted: Display.refresh()

            // ── OLED / panel care ──
            Card {
                visible: !!Display.internal
                height: oledCol.implicitHeight + 24
                border.color: Display.hasOled ? Theme.alpha(Theme.accent, 0.4) : Theme.border
                Column {
                    id: oledCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8
                    Row {
                        spacing: 10
                        Icon { name: "monitor"; size: 18; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            Text {
                                text: Display.internal ? (Display.internal.model || Display.internal.name)
                                    + (Display.hasOled ? "   OLED" : "") : ""
                                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold
                            }
                            Text {
                                text: Display.internal ? `${Display.internal.w}×${Display.internal.h} · ${Display.internal.refresh} Hz`
                                    + (Display.internal.hdr_nits ? ` · HDR ${Math.round(Display.internal.hdr_nits)} nits` : "")
                                    + (Display.internal.vendor ? ` · ${Display.internal.vendor}` : "") : ""
                                color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs
                            }
                        }
                    }
                    SettingRow {
                        label: "Project (Super+P)"
                        description: "Quickly switch display layout when an external monitor is connected."
                        Segmented {
                            options: [
                                { value: "pc", label: "PC screen only" },
                                { value: "duplicate", label: "Duplicate" },
                                { value: "extend", label: "Extend" },
                                { value: "second", label: "Second screen only" }
                            ]
                            // Rough heuristic to show which state we might be in
                            value: {
                                const m = Hyprland.monitors.values;
                                if (m.length === 1) return m[0].name.startsWith("eDP") ? "pc" : "second";
                                if (m.length > 1) {
                                    if (m[1].x === 0 && m[1].y === 0 && m[0].x === 0 && m[0].y === 0) return "duplicate";
                                    return "extend";
                                }
                                return "pc";
                            }
                            onSelected: v => Display.setProjection(v)
                        }
                    }
                    SettingRow {
                        label: "Brightness"
                        description: "10–100 %. The floor keeps an OLED panel from going fully black."
                        Slider {
                            width: 240; icon: "sun"
                            value: (Power.brightness - Power.minBrightness) / (1 - Power.minBrightness)
                            valueText: Math.round((Power.minBrightness + (1 - Power.minBrightness) * shown) * 100) + "%"
                            onMoved: v => Power.setBrightness(Power.minBrightness + (1 - Power.minBrightness) * v)
                        }
                    }
                    SettingRow {
                        label: "Refresh rate"
                        description: "120 Hz is smooth; 60 Hz saves battery. Applies to the internal display."
                        Segmented {
                            options: [{ value: 60, label: "60 Hz" }, { value: 120, label: "120 Hz" }]
                            value: Display.internal ? Display.internal.refresh : 120
                            onSelected: v => Display.setRefresh(Display.internal.name, v)
                        }
                    }
                    SettingRow {
                        visible: Display.hasOled
                        label: "OLED care  ★ recommended"
                        description: "Runs hypridle: dims after 4 min (wakes instantly), locks after 12, suspends on battery after 25. No screen-blanking — safe for this OLED. Off by default."
                        Toggle { checked: Display.hypridleOn; onToggled: v => Display.setOledCare(v) }
                    }
                }
            }

            Repeater {
                model: Hyprland.monitors.values
                Card {
                    required property var modelData
                    readonly property var ipc: modelData.lastIpcObject || ({})
                    readonly property var modes: (ipc.availableModes || []).slice(0, 14)
                    height: mcol.implicitHeight + 24
                    Column {
                        id: mcol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 8
                        Row {
                            spacing: 10
                            Icon { name: "monitor"; size: 18; color: modelData.focused ? Theme.accent : Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                            Column {
                                Text { text: modelData.name + (ipc.description ? "  ·  " + ipc.description : ""); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold; elide: Text.ElideRight; width: mcol.width - 40 }
                                Text { text: `${modelData.width}×${modelData.height} @ ${Math.round(ipc.refreshRate || 0)} Hz  ·  scale ${modelData.scale}  ·  position ${modelData.x},${modelData.y}`; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs }
                            }
                        }
                        Text { text: "MODE"; color: Theme.muted; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; topPadding: 4 }
                        Flow {
                            width: parent.width; spacing: 6
                            Repeater {
                                model: modes
                                Btn {
                                    required property var modelData
                                    readonly property bool cur: modelData.startsWith(`${mcol.parent.modelData.width}x${mcol.parent.modelData.height}@${Math.round(ipc.refreshRate || 0)}`)
                                    label: modelData.replace(".00Hz", "Hz").replace(/\.\d+Hz/, "Hz"); active: cur
                                    onClicked: HyprOpts.monitor(mcol.parent.modelData.name, modelData.split('Hz')[0].replace('.00', ''), `${mcol.parent.modelData.x}x${mcol.parent.modelData.y}`, mcol.parent.modelData.scale)
                                }
                            }
                        }
                        Text { text: "SCALE"; color: Theme.muted; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; topPadding: 4 }
                        Segmented {
                            options: [{ value: 1, label: "1×" }, { value: 1.25, label: "1.25×" }, { value: 1.5, label: "1.5×" }, { value: 2, label: "2×" }]
                            value: modelData.scale
                            // mode = PHYSICAL resolution (never × scale); scale is a separate arg
                            onSelected: v => HyprOpts.monitor(modelData.name, `${modelData.width}x${modelData.height}@${Math.round(ipc.refreshRate || 60)}`, `${modelData.x}x${modelData.y}`, v)
                        }
                        Text { text: "POSITION"; color: Theme.muted; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; topPadding: 4 }
                        Segmented {
                            options: [
                                { value: "auto-left", label: "Left" },
                                { value: "auto-right", label: "Right" },
                                { value: "auto-up", label: "Up" },
                                { value: "auto-down", label: "Down" },
                                { value: "0x0", label: "Mirror" }
                            ]
                            // Simple heuristic for current value:
                            value: modelData.x === 0 && modelData.y === 0 ? "0x0" : (modelData.x < 0 ? "auto-left" : (modelData.y < 0 ? "auto-up" : "auto-right"))
                            onSelected: v => HyprOpts.monitor(modelData.name, `${modelData.width}x${modelData.height}@${Math.round(ipc.refreshRate || 60)}`, v, modelData.scale)
                        }
                    }
                }
            }
            SettingRow {
                label: "Eye Comfort (Night Light)"
                description: "Reduces blue light to help reduce eye strain at night."
                Toggle { checked: EyeComfort.enabled; onToggled: EyeComfort.toggle() }
            }
            SettingRow {
                label: "Eye Comfort Intensity"
                description: "Adjust the intensity of the blue light filter."
                Slider {
                    width: 220; icon: "sun"
                    value: EyeComfort.intensity; valueText: Math.round(EyeComfort.intensity * 100) + "%"
                    fillColor: EyeComfort.enabled ? Theme.accent : Theme.muted
                    onMoved: v => EyeComfort.intensity = v
                }
            }
            Text { text: "Applies immediately (hl.monitor via hyprctl eval). To make it permanent, put the same hl.monitor{} block in hyprland.lua."; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; width: parent.width; wrapMode: Text.WordWrap }
        }
    }

    // ═══════════════ WINDOWS ═══════════════
    Component {
        id: windowsSec
        Column {
            spacing: 0
            SettingRow { label: "Inner gaps"; description: HyprOpts.gapsIn + " px"
                Slider { width: 220; icon: "layers"; value: HyprOpts.gapsIn / 30; valueText: ""; onMoved: v => HyprOpts.set("general:gaps_in", Math.round(v * 30)) } }
            SettingRow { label: "Outer gaps"; description: HyprOpts.gapsOut + " px"
                Slider { width: 220; icon: "layers"; value: HyprOpts.gapsOut / 60; valueText: ""; onMoved: v => HyprOpts.set("general:gaps_out", Math.round(v * 60)) } }
            SettingRow { label: "Border size"; description: HyprOpts.border + " px"
                Slider { width: 220; icon: "layers"; value: HyprOpts.border / 6; valueText: ""; onMoved: v => HyprOpts.set("general:border_size", Math.round(v * 6)) } }
            SettingRow { label: "Window rounding"; description: HyprOpts.rounding + " px"
                Slider { width: 220; icon: "layers"; value: HyprOpts.rounding / 30; valueText: ""; onMoved: v => HyprOpts.set("decoration:rounding", Math.round(v * 30)) } }
            SettingRow { label: "Active window opacity"; description: Math.round(HyprOpts.activeOpacity * 100) + "%"
                Slider { width: 220; icon: "eye"; value: HyprOpts.activeOpacity; valueText: ""; onMoved: v => HyprOpts.set("decoration:active_opacity", Math.max(0.5, v).toFixed(2)) } }
            SettingRow { label: "Animations"; Toggle { checked: HyprOpts.animations; onToggled: v => HyprOpts.set("animations:enabled", v ? 1 : 0) } }
            Text { text: "Live via hl.config — persists until the next Hyprland restart unless copied into hyprland.lua."; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; width: parent.width; wrapMode: Text.WordWrap; topPadding: 10 }
        }
    }

    // ═══════════════ KEYBOARD ═══════════════
    Component {
        id: keyboard
        Column {
            spacing: 0
            H { text: "SHELL" }
            Repeater {
                model: [["Super + A", "Launcher / search"], ["Super + W", "Launcher / search"], ["Super + I", "AI panel"], ["Super + O", "Control Center"], ["Super + Escape", "Restart shell"]]
                SettingRow { label: modelData[1]; Text { text: modelData[0]; color: Theme.accent; font.family: Theme.fontMono; font.pixelSize: Theme.fontSm } }
            }
            H { text: "HYPRLAND  (" + win.bindList.length + " binds, live from hyprctl)" }
            Repeater {
                model: win.bindList
                SettingRow { label: modelData.action; Text { text: modelData.keys; color: Theme.text2; font.family: Theme.fontMono; font.pixelSize: Theme.fontXs } }
            }
        }
    }

    // ═══════════════ NETWORK ═══════════════
    Component {
        id: network
        Column {
            spacing: 0
            Component.onCompleted: Net.scan()
            SettingRow { label: "Wi-Fi"; description: Net.label; Toggle { checked: Net.wifiEnabled; onToggled: v => Net.setWifi(v) } }
            SettingRow { label: "Connectivity"; description: Net.online ? "Internet reachable" : "Limited or offline"
                Btn { icon: "gear"; label: "Network Manager"; onClicked: { Shell.run("nm-connection-editor"); Shell.closeAll() } } }
            H { text: "NETWORKS" }
            Repeater {
                model: Net.wifiNetworks.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))
                Column {
                    required property var modelData
                    width: parent.width
                    SettingRow {
                        label: modelData.name || "(hidden)"
                        description: (modelData.connected ? "Connected · " : modelData.known ? "Saved · " : "") + Math.round(modelData.signalStrength) + "% signal"
                        Row {
                            spacing: 6
                            Icon { name: "wifi"; size: 14; color: modelData.connected ? Theme.accent : Theme.muted; opacity: 0.4 + 0.6 * modelData.signalStrength / 100; anchors.verticalCenter: parent.verticalCenter }
                            Btn { visible: modelData.connected; icon: "x"; label: "Disconnect"; onClicked: modelData.disconnect() }
                            Btn { visible: !modelData.connected && modelData.known; icon: "check"; label: "Connect"; onClicked: modelData.connect() }
                            Btn { visible: !modelData.connected && !modelData.known; icon: "lock"; label: "Join"; onClicked: win.wifiPskFor = modelData.name }
                            Btn { visible: modelData.known && !modelData.connected; icon: "trash"; onClicked: modelData.forget() }
                        }
                    }
                    Rectangle {
                        visible: win.wifiPskFor === modelData.name && !modelData.connected
                        width: parent.width; height: 40; radius: 20
                        color: Theme.alpha(Theme.text, 0.06); border.width: 1; border.color: Theme.alpha(Theme.accent, 0.5)
                        TextInput { id: psk; anchors { fill: parent; leftMargin: 14; rightMargin: 90 }
                            verticalAlignment: TextInput.AlignVCenter; echoMode: TextInput.Password; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; focus: visible
                            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: !psk.text; text: "Password"; color: Theme.muted; font: psk.font }
                            Keys.onReturnPressed: { modelData.connectWithPsk(psk.text); psk.text = ""; win.wifiPskFor = "" } }
                        Btn { anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
                            icon: "check"; label: "Join"; active: true; iconColor: Theme.onAccent; onClicked: { modelData.connectWithPsk(psk.text); psk.text = ""; win.wifiPskFor = "" } }
                    }
                }
            }
        }
    }

    // ═══════════════ BLUETOOTH ═══════════════
    Component {
        id: bluetooth
        Column {
            spacing: 0
            SettingRow { label: "Bluetooth"; description: Net.btLabel; Toggle { enabled: Net.btAvailable; checked: Net.btEnabled; onToggled: v => Net.setBt(v) } }
            SettingRow { label: "Discover new devices"; description: Net.adapter && Net.adapter.discovering ? "Scanning…" : "Off"
                Toggle { enabled: Net.btEnabled; checked: Net.adapter ? Net.adapter.discovering : false; onToggled: v => Net.setDiscovering(v) } }
            H { text: "DEVICES" }
            Repeater {
                model: Net.btDevices.slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired))
                SettingRow {
                    required property var modelData
                    label: modelData.name || modelData.deviceName || modelData.address
                    description: (modelData.connected ? "Connected" : modelData.paired ? "Paired" : "Available") + (modelData.batteryAvailable ? " · battery " + Math.round(modelData.battery * 100) + "%" : "")
                    Row {
                        spacing: 6
                        Btn { visible: modelData.connected; icon: "x"; label: "Disconnect"; onClicked: modelData.disconnect() }
                        Btn { visible: !modelData.connected && modelData.paired; icon: "check"; label: "Connect"; onClicked: modelData.connect() }
                        Btn { visible: !modelData.paired; icon: "plus"; label: modelData.pairing ? "Pairing…" : "Pair"; onClicked: modelData.pair() }
                        Btn { visible: modelData.paired; icon: "trash"; onClicked: modelData.forget() }
                    }
                }
            }
            Btn { icon: "gear"; label: "Blueman manager"; onClicked: { Shell.run("blueman-manager"); Shell.closeAll() } }
        }
    }

    // ═══════════════ AUDIO ═══════════════
    Component {
        id: audio
        Column {
            spacing: 0
            SettingRow { label: "Output volume"; description: Audio.sinkName
                Slider { width: 240; icon: Audio.icon; value: Audio.muted ? 0 : Audio.volume; onMoved: v => Audio.setVolume(v); onIconClicked: Audio.toggleMute() } }
            SettingRow { label: "Input volume"; description: Audio.sourceName
                Slider { width: 240; icon: "mic"; fillColor: Theme.green; value: Audio.micMuted ? 0 : Audio.micVolume; onMoved: v => Audio.setMicVolume(v); onIconClicked: Audio.toggleMicMute() } }
            H { text: "OUTPUT DEVICE" }
            Repeater {
                model: Audio.sinks
                SettingRow { required property var modelData; label: modelData.description || modelData.nickname || modelData.name
                    Btn { icon: Audio.sink === modelData ? "check" : "volume-high"; label: Audio.sink === modelData ? "Default" : "Use"; active: Audio.sink === modelData; iconColor: active ? Theme.onAccent : Theme.text2; onClicked: Audio.setDefaultSink(modelData) } }
            }
            H { text: "INPUT DEVICE" }
            Repeater {
                model: Audio.sources
                SettingRow { required property var modelData; label: modelData.description || modelData.nickname || modelData.name
                    Btn { icon: Audio.source === modelData ? "check" : "mic"; label: Audio.source === modelData ? "Default" : "Use"; active: Audio.source === modelData; iconColor: active ? Theme.onAccent : Theme.text2; onClicked: Audio.setDefaultSource(modelData) } }
            }
            Btn { icon: "gear"; label: "PulseAudio Volume Control"; onClicked: { Shell.run("pavucontrol"); Shell.closeAll() } }
        }
    }

    // ═══════════════ POWER ═══════════════
    Component {
        id: powerSec
        Column {
            spacing: 0
            readonly property var bat: UPower.displayDevice
            SettingRow { label: "Thermal & power mode"; description: "Sets both Linux power policy and supported ASUS firmware cooling behaviour."
                Segmented { options: [{ value: "power-saver", label: "Quiet" }, { value: "balanced", label: "Balanced" }, { value: "performance", label: "Performance" }]; value: Power.profile; onSelected: v => { Power.profile = v; win.hwSet("profile", v) } } }
            H { text: "BATTERY" }
            Repeater {
                model: bat ? [["Charge", Math.round((bat.percentage > 1 ? bat.percentage : bat.percentage * 100)) + "%"],
                              ["State", ["Unknown", "Charging", "Discharging", "Empty", "Fully charged", "Pending charge", "Pending discharge"][bat.state] || "—"],
                              ["Health", bat.healthSupported ? Math.round(bat.healthPercentage) + "%" : "n/a"],
                              ["Energy", bat.energy.toFixed(1) + " / " + bat.energyCapacity.toFixed(1) + " Wh"],
                              ["Rate", Math.abs(bat.changeRate).toFixed(1) + " W"],
                              ["Model", bat.model || "—"]] : []
                SettingRow { label: modelData[0]; Text { text: modelData[1]; color: Theme.text2; font.family: Theme.fontMono; font.pixelSize: Theme.fontSm } }
            }
            H { text: "ASUS HARDWARE  —  " + (win.hw.model || "") }
            SettingRow { label: "Fan"; description: (win.hw.fans ? win.hw.fans.rpm + " rpm · " : "") + "Firmware-managed on this Vivobook. Cooling changes with the Thermal & power mode above."; Icon { name: "fan"; size: 14; color: Theme.muted } }
            SettingRow { label: "Keyboard backlight"
                Segmented { options: [{ value: 0, label: "Off" }, { value: 1, label: "Low" }, { value: 2, label: "Mid" }, { value: 3, label: "High" }]; value: win.hw.keyboard ? win.hw.keyboard.level : 0; onSelected: v => win.hwSet("keyboard", String(v)) } }
            SettingRow { label: "Battery charge limit"; description: "Stops charging at this level to extend battery life."
                Segmented { options: [{ value: 60, label: "60%" }, { value: 80, label: "80%" }, { value: 100, label: "100%" }]; value: win.hw.battery ? win.hw.battery.charge_limit : 100; onSelected: v => win.hwSet("charge_limit", String(v)) } }
            SettingRow {
                readonly property var mux: (win.hw.gpu && win.hw.gpu.mux) || ({})
                visible: !!mux.supported
                label: "GPU mode"
                description: mux.pending_reboot ? "Restart to finish switching the GPU mode."
                    : mux.value === "1" ? "Hybrid: the Intel GPU draws the desktop; the NVIDIA GPU sleeps until something needs it — AI models, games, or a monitor on its HDMI port. Best for battery."
                    : "NVIDIA only: the NVIDIA GPU draws every screen — most GPU performance, but it never sleeps (~15 W at idle)."
                Segmented { options: [{ value: "1", label: "Hybrid" }, { value: "0", label: "NVIDIA only" }]; value: parent.mux.value || ""
                    onSelected: v => win.hwSet("gpu_mux", v === "1" ? "hybrid" : "dgpu") }
            }
            SettingRow { label: "Temperatures"; description: win.hw.temps ? Object.keys(win.hw.temps).map(k => k + " " + win.hw.temps[k] + "°C").join(" · ") : "…"; Icon { name: "sun"; size: 14; color: Theme.muted } }
            H { text: "SESSION" }
            SettingRow { label: "Lock screen"; Btn { icon: "lock"; label: "Lock now"; onClicked: { Power.lock(); Shell.closeAll() } } }
            SettingRow { label: "Suspend"; Btn { icon: "moon"; label: "Sleep now"; onClicked: { Power.suspend(); Shell.closeAll() } } }
        }
    }

    // ═══════════════ WALLPAPER ═══════════════
    Component {
        id: wallpaper
        Column {
            spacing: 10
            H { text: "STILL"; topPadding: 0 }
            Text { text: "Images in ~/.local/share/wallpapers. Click to apply to all monitors."; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs }
            Flow {
                width: parent.width; spacing: 10
                Repeater {
                    model: Wallpaper.files
                    Rectangle {
                        required property var modelData
                        readonly property bool cur: !Wallpaper.isLive && Wallpaper.current === modelData
                        width: 200; height: 118; radius: Theme.radiusMd; clip: true
                        color: Theme.surface3
                        border.width: cur ? 3 : 1; border.color: cur ? Theme.accent : Theme.border
                        Image { anchors.fill: parent; anchors.margins: 2; source: "file://" + modelData; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(400, 240) }
                        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 24; color: Theme.alpha(Theme.bg, 0.7)
                            Text { anchors.centerIn: parent; text: modelData.split("/").pop().replace(/\.[^.]+$/, ""); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; width: parent.width - 12; horizontalAlignment: Text.AlignHCenter } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Wallpaper.apply(modelData) }
                    }
                }
            }

            H { text: "LIVE" }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: Wallpaper.liveSupported
                    ? "Looping videos from ~/.local/share/wallpapers/live. They pause while windows cover them, and the ambient glow steps aside while one plays."
                    : "Live wallpapers need mpvpaper. Install it with:  yay -S mpvpaper"
                color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs
            }
            SettingRow {
                visible: Wallpaper.liveSupported
                label: "Play on battery"
                description: Wallpaper.liveSuspended ? "On battery now — showing the still image; the video resumes when you plug in."
                                                     : "Off saves power: the still image shows while unplugged."
                Toggle { checked: Settings.liveOnBattery; onToggled: v => Settings.liveOnBattery = v }
            }
            Flow {
                width: parent.width; spacing: 10
                visible: Wallpaper.liveSupported
                Repeater {
                    model: Wallpaper.videos
                    Rectangle {
                        id: vt
                        required property var modelData
                        readonly property bool cur: Wallpaper.isLive && Wallpaper.live === modelData.path
                        width: 200; height: 118; radius: Theme.radiusMd; clip: true
                        color: Theme.surface3
                        border.width: cur ? 3 : 1; border.color: cur ? Theme.accent : Theme.border
                        Image { anchors.fill: parent; anchors.margins: 2; source: vt.modelData.thumb ? "file://" + vt.modelData.thumb : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(400, 240) }
                        Rectangle {
                            x: 8; y: 8; height: 18; radius: 9; width: liveTag.implicitWidth + 14
                            color: vt.cur ? Theme.accent : Theme.alpha(Theme.bg, 0.75)
                            Text { id: liveTag; anchors.centerIn: parent; text: !vt.cur ? "LIVE" : Wallpaper.liveSuspended ? "❚❚ ON AC" : "● LIVE"; color: vt.cur ? Theme.onAccent : Theme.text
                                font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
                        }
                        Rectangle {
                            anchors.centerIn: parent; anchors.verticalCenterOffset: -8
                            width: 40; height: 40; radius: 20
                            visible: !vt.cur
                            color: Theme.alpha(Theme.bg, vma.containsMouse ? 0.85 : 0.55)
                            Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; name: "play"; size: 18; color: Theme.text }
                        }
                        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 24; color: Theme.alpha(Theme.bg, 0.7)
                            Text { anchors.centerIn: parent; text: vt.modelData.path.split("/").pop().replace(/\.[^.]+$/, ""); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; width: parent.width - 12; horizontalAlignment: Text.AlignHCenter } }
                        MouseArea { id: vma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Wallpaper.applyLive(vt.modelData.path) }
                    }
                }
            }
            Row { spacing: 6
                Btn { icon: "pause"; label: "Stop live wallpaper"; visible: Wallpaper.isLive; onClicked: Wallpaper.stopLive() }
                Btn { icon: "refresh"; label: "Rescan"; onClicked: Wallpaper.refresh() }
                Btn { icon: "image"; label: "Open folder"; onClicked: { Shell.run("thunar ~/.local/share/wallpapers"); Shell.closeAll() } }
            }
        }
    }

    // ═══════════════ PROFILES ═══════════════
    Component {
        id: profiles
        Column {
            spacing: 10
            Repeater {
                model: [
                    { id: "Normal", desc: "Balanced everyday desktop. Blue accent, stats hidden.", color: Theme.blue },
                    { id: "Development", desc: "Purple accent, CPU/RAM/GPU in the bar, performance power profile.", color: Theme.purple },
                    { id: "Cyber Lab", desc: "Green accent, all stats visible, notifications on.", color: Theme.green },
                    { id: "Presentation", desc: "Neutral accent, stats hidden, Do Not Disturb on, animations snappy.", color: Theme.text },
                ]
                Card {
                    required property var modelData
                    readonly property bool on: Settings.profile === modelData.id
                    height: 64
                    border.color: on ? Theme.alpha(modelData.color, 0.6) : Theme.border
                    color: on ? Theme.alpha(modelData.color, 0.10) : Theme.alpha(Theme.text, 0.04)
                    Row {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 12
                        Rectangle { width: 14; height: 14; radius: 7; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: modelData.id; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontMd; font.weight: Font.DemiBold }
                            Text { text: modelData.desc; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs }
                        }
                    }
                    Icon { visible: on; name: "check"; size: 16; color: modelData.color; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } }
                    MouseArea { anchors.fill: parent; onClicked: Settings.profile = modelData.id }
                }
            }
        }
    }

    // ═══════════════ AI ═══════════════
    Component {
        id: ai
        Column {
            spacing: 0
            H { text: "WHICH BRAIN ANSWERS  —  applies to the shell, browser UI, CLI and voice" }
            SettingRow {
                label: "Auto routing   ★ recommended"; description: "Classifies each request (code / debug / system / reasoning / chat / image) and picks the best available model. Keeps the loaded model when it is close enough, to avoid a 10–20 s swap."
                Btn { icon: Aios.autoRouting ? "check" : "layers"; label: Aios.autoRouting ? "Selected" : "Use"; active: Aios.autoRouting; iconColor: active ? Theme.onAccent : Theme.text2; onClicked: Aios.selectModel("auto") }
            }
            Repeater {
                model: Aios.models.filter(m => m.provider === "local")
                SettingRow {
                    required property var modelData
                    label: modelData.label + "  ·  " + modelData.role + "   " + "★".repeat(modelData.quality) + "☆".repeat(5 - modelData.quality)
                    description: modelData.note + "  ·  " + modelData.speed + (modelData.measured && modelData.measured.tok_per_s ? " (" + modelData.measured.tok_per_s + " tok/s measured here)" : "") + "  ·  VRAM " + modelData.vram + "  ·  RAM " + modelData.ram
                    Btn {
                        icon: modelData.id === Aios.selectedModel ? "check" : modelData.paid ? "cloud" : "chip"
                        label: modelData.id === Aios.selectedModel ? "Selected" : !modelData.available ? (modelData.paid ? "Needs key" : "Downloading…") : "Use"
                        active: modelData.id === Aios.selectedModel; iconColor: active ? Theme.onAccent : Theme.text2
                        opacity: modelData.available ? 1 : 0.5
                        onClicked: if (modelData.available) Aios.selectModel(modelData.id)
                    }
                }
            }
            H { text: "CLOUD  —  " + (Aios.netOnline ? "internet reachable" : "OFFLINE: local models only") }
            SettingRow { label: "Let auto routing use cloud for"; description: "Only when a provider is configured and the budget mode allows it. Empty = never leave the machine automatically."
                Flow { width: 300; spacing: 4
                    Repeater { model: ["code", "debug", "sysadmin", "reasoning", "general"]
                        Btn { required property var modelData; label: modelData; active: Aios.preferCloudFor.indexOf(modelData) >= 0; iconSize: 0; icon: ""
                              onClicked: { const l = Aios.preferCloudFor.slice(); const i = l.indexOf(modelData); if (i >= 0) l.splice(i, 1); else l.push(modelData); Aios.setCloudFor(l) } } } } }
            Repeater {
                model: Aios.providers
                SettingRow {
                    required property var modelData
                    label: modelData.name + "   " + (modelData.paid ? "paid" : "free tier")
                    description: (modelData.enabled ? "enabled" : "disabled in providers.json") + " · key " + (modelData.configured ? "set" : "missing (" + modelData.key_env + " in aios.env)") + " · " + modelData.state + (modelData.reason ? " — " + modelData.reason : "") + " · quota " + modelData.quota + " · " + modelData.models.join(", ")
                    Icon { name: "cloud"; size: 14; color: modelData.state === "ok" ? Theme.green : modelData.state === "quota" || modelData.state === "offline" ? Theme.yellow : Theme.muted }
                }
            }
            H { text: "COST" }
            SettingRow { label: "Budget mode"; description: Aios.budgetMode === "ZERO_COST" || Aios.budgetMode === "LOCAL_ONLY" ? "No request can ever reach a paid provider." : Aios.budgetMode === "APPROVAL" ? "Each paid request must be approved first." : "Paid providers allowed (keys required)."
                Segmented { options: [{ value: "ZERO_COST", label: "₹0 local" }, { value: "FREE_ONLINE", label: "Free tiers" }, { value: "APPROVAL", label: "Ask first" }, { value: "UNRESTRICTED", label: "Open" }]; value: Aios.budgetMode === "LOCAL_ONLY" ? "ZERO_COST" : Aios.budgetMode; onSelected: v => Aios.setBudget(v) } }
            H { text: "BEHAVIOUR" }
            SettingRow { label: "Deep thinking"; description: "Qwen3 reasoning mode. Much better on hard questions, several times slower."; Toggle { checked: Aios.thinking; onToggled: v => Aios.setThinking(v) } }
            SettingRow { label: "Model in VRAM"; description: Aios.loadedModel ? Aios.loadedModel + " is loaded (auto-unloads after 2 min idle)" : "Nothing loaded — VRAM is free"
                Btn { visible: Aios.loadedModel !== ""; icon: "gpu"; label: "Free VRAM now"; onClicked: Aios.unload() } }
            SettingRow { label: "Memory & usage"; description: Aios.memoryObjects + " objects in the context store · " + Aios.runs + " model runs in the ledger · `ai usage` for per-model tokens, latency and failure rate"
                Row { spacing: 6
                    Btn { icon: "eye"; label: "Activity"; onClicked: Shell.open("activity") }
                    Btn { icon: "arrow"; label: "Open full UI"; onClicked: Shell.run("google-chrome-stable --app=http://127.0.0.1:8778 --class=aios") } } }
            H { text: "CLOUD PROVIDERS" }
            Text { text: "Add ANTHROPIC_API_KEY to ~/aios/config/aios.env and restart the service to enable Claude. Nothing is sent to a provider unless the budget mode allows it and you selected that model."; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; width: parent.width; wrapMode: Text.WordWrap; topPadding: 4 }
        }
    }
}
