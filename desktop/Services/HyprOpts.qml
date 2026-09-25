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

    readonly property var _names: ["general:gaps_in", "general:gaps_out", "general:border_size",
                                   "decoration:rounding", "decoration:blur:enabled", "animations:enabled",
                                   "decoration:active_opacity"]

    function refresh() { if (!probe.running) probe.running = true }

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
