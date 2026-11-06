pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live Hyprland options (read via hyprctl getoption, written via keyword).
Singleton {
    id: root

    property int  gapsIn: 5
    property int  gapsOut: 10
    property int  border: 2
    property int  rounding: 10
    property bool blur: true
    property bool animations: true
    property real activeOpacity: 1.0
    property string hyprVersion: ""

    // Touchpad & Pointer controls
    property real touchpadSensitivity: 0.0
    property real touchpadScrollFactor: 1.0
    property bool touchpadNaturalScroll: false
    property bool touchpadTapToClick: true
    property bool touchpadTapAndDrag: true
    property var  touchpadsList: []

    readonly property var _names: ["general:gaps_in", "general:gaps_out", "general:border_size",
                                   "decoration:rounding", "decoration:blur:enabled", "animations:enabled",
                                   "decoration:active_opacity"]

    function refresh() {
        if (!probe.running) probe.running = true
        if (!touchpadProbe.running) touchpadProbe.running = true
    }

    Process {
        id: touchpadProbe
        command: ["praxis-touchpad", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    if (d.sensitivity !== undefined) root.touchpadSensitivity = d.sensitivity
                    if (d.scroll_factor !== undefined) root.touchpadScrollFactor = d.scroll_factor
                    if (d.natural_scroll !== undefined) root.touchpadNaturalScroll = !!d.natural_scroll
                    if (d.tap_to_click !== undefined) root.touchpadTapToClick = !!d.tap_to_click
                    if (d.tap_and_drag !== undefined) root.touchpadTapAndDrag = !!d.tap_and_drag
                    if (d.touchpads) root.touchpadsList = d.touchpads
                } catch (e) {}
            }
        }
    }
    Timer { id: refreshTouchpadsLater; interval: 400; onTriggered: if (!touchpadProbe.running) touchpadProbe.running = true }

    function setTouchpadSensitivity(v) {
        root.touchpadSensitivity = v
        Quickshell.execDetached(["praxis-touchpad", "set-sensitivity", v.toFixed(2)])
    }
    function setTouchpadScrollFactor(v) {
        root.touchpadScrollFactor = v
        Quickshell.execDetached(["praxis-touchpad", "set-scroll-factor", v.toFixed(2)])
    }
    function setTouchpadNaturalScroll(v) {
        root.touchpadNaturalScroll = v
        Quickshell.execDetached(["praxis-touchpad", "set-natural-scroll", v ? "true" : "false"])
    }
    function setTouchpadTapToClick(v) {
        root.touchpadTapToClick = v
        Quickshell.execDetached(["praxis-touchpad", "set-tap-to-click", v ? "true" : "false"])
    }
    function setTouchpadTapAndDrag(v) {
        root.touchpadTapAndDrag = v
        Quickshell.execDetached(["praxis-touchpad", "set-tap-and-drag", v ? "true" : "false"])
    }
    function setDeviceSensitivity(devName, v) {
        Quickshell.execDetached(["praxis-touchpad", "set-device", devName, v.toFixed(2)])
        refreshTouchpadsLater.start()
    }
    function resetDevice(devName) {
        Quickshell.execDetached(["praxis-touchpad", "reset-device", devName])
        refreshTouchpadsLater.start()
    }

    Process {
        id: probe
        command: ["bash", "-c", root._names.map(n => `hyprctl -j getoption ${n} | tr -d '\\n'`).join("; echo; ") + "; echo; hyprctl -j version | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("\n").map(s => s.trim()).filter(s => s.startsWith("{"))
                const val = o => o.int !== undefined ? o.int : o.float !== undefined ? o.float : o.custom !== undefined ? o.custom : 0
                try {
                    if (parts.length >= 7) {
                        const g = parts.map(p => JSON.parse(p))
                        // gaps come back as custom "5 5 5 5" strings or ints depending on version
                        const num = o => { const v = val(o); return typeof v === "string" ? parseInt(v.split(" ")[0]) : v }
                        root.gapsIn = num(g[0]); root.gapsOut = num(g[1]); root.border = num(g[2])
                        root.rounding = num(g[3]); root.blur = !!num(g[4]); root.animations = !!num(g[5])
                        root.activeOpacity = parseFloat(val(g[6])) || 1.0
                    }
                    if (parts.length >= 8) { const v = JSON.parse(parts[7]); root.hyprVersion = (v.tag && v.tag !== "" ? v.tag : (v.version || "")) || (v.commit ? v.commit.slice(0, 8) : "") }
                } catch (e) {}
            }
        }
    }

    // hyprland.lua uses the Lua parser: options change via `hyprctl eval 'hl.config{…}'`
    function set(name, value) {
        const lua = {
            "general:gaps_in":           `hl.config({ general = { gaps_in = ${value} } })`,
            "general:gaps_out":          `hl.config({ general = { gaps_out = ${value} } })`,
            "general:border_size":       `hl.config({ general = { border_size = ${value} } })`,
            "decoration:rounding":       `hl.config({ decoration = { rounding = ${value} } })`,
            "decoration:blur:enabled":   `hl.config({ decoration = { blur = { enabled = ${value ? "true" : "false"} } } })`,
            "animations:enabled":        `hl.config({ animations = { enabled = ${value ? "true" : "false"} } })`,
            "decoration:active_opacity": `hl.config({ decoration = { active_opacity = ${value} } })`,
        }[name]
        if (!lua) return
        Quickshell.execDetached(["hyprctl", "eval", lua])
        switch (name) {
            case "general:gaps_in": gapsIn = value; break
            case "general:gaps_out": gapsOut = value; break
            case "general:border_size": border = value; break
            case "decoration:rounding": rounding = value; break
            case "decoration:blur:enabled": blur = !!value; break
            case "animations:enabled": animations = !!value; break
            case "decoration:active_opacity": activeOpacity = value; break
        }
    }
    function dispatch(lua) { Quickshell.execDetached(["hyprctl", "dispatch", lua]) }
    function monitor(output, mode, position, scale) {
        Quickshell.execDetached(["hyprctl", "eval", `hl.monitor({ output = "${output}", mode = "${mode}", position = "${position}", scale = ${scale} })`])
    }
    Component.onCompleted: refresh()
}
