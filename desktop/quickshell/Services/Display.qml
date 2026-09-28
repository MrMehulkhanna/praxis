pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "root:/Config"

// Display + OLED care. Reads panel identity from EDID (Samsung ATNA = OLED),
// switches refresh rate live, and manages hypridle (burn-in protection).
Singleton {
    id: root

    property var panels: []          // [{name, w, h, refresh, scale, oled, vendor, model, hdr_nits}]
    property bool hypridleOn: false
    property bool refreshProbed: false

    function refresh() { if (!probe.running) probe.running = true; hypridleCheck() }

    // ── EDID + monitor probe ────────────────────────────────────────────
    Process {
        id: probe
        command: ["bash", "-c", `
for e in /sys/class/drm/card*-eDP-*/edid /sys/class/drm/card*-DP-*/edid /sys/class/drm/card*-HDMI-*/edid; do
  [ -f "$e" ] || continue
  conn=$(basename $(dirname "$e") | sed 's/^card[0-9]*-//')
  vendor=""; model=""; oled=0; nits=""
  if command -v edid-decode >/dev/null 2>&1; then
    dec=$(edid-decode "$e" 2>/dev/null)
    vendor=$(echo "$dec" | sed -n 's/.*Manufacturer: *//p' | head -1)
    model=$(echo "$dec" | sed -n 's/.*Display Product Name: .*//p' | head -1)
    nits=$(echo "$dec" | sed -n "s/.*max luminance: [0-9]* (\\([0-9.]*\\) cd.*/\\1/p" | head -1)
  fi
  raw=$(strings "$e" 2>/dev/null | head -1)
  # Samsung OLED panels start with ATNA; also treat SDC vendor + known prefixes
  case "$raw" in ATNA*) oled=1 ;; esac
  echo "PANEL|$conn|$vendor|$raw|$oled|$nits"
done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const byConn = {}
                for (const l of this.text.trim().split("\n")) {
                    if (!l.startsWith("PANEL|")) continue
                    const [, conn, vendor, raw, oled, nits] = l.split("|")
                    byConn[conn] = { vendor, model: raw, oled: oled === "1", hdr_nits: nits }
                }
                const out = []
                for (const m of Hyprland.monitors.values) {
                    const ipc = m.lastIpcObject || {}
                    const e = byConn[m.name] || {}
                    out.push({ name: m.name, w: m.width, h: m.height, refresh: Math.round(ipc.refreshRate || 0),
                               scale: m.scale, x: m.x, y: m.y, modes: ipc.availableModes || [],
                               oled: !!e.oled, vendor: e.vendor || "", model: e.model || "", hdr_nits: e.hdr_nits || "" })
                }
                root.panels = out
                root.refreshProbed = true
            }
        }
    }

    readonly property var internal: {
        for (const p of panels) if (p.name.startsWith("eDP")) return p
        return panels.length ? panels[0] : null
    }
    readonly property bool hasOled: panels.some(p => p.oled)

    // ── refresh rate ────────────────────────────────────────────────────
    function setRefresh(name, hz) {
        const p = panels.find(x => x.name === name)
        if (!p) return
        // mode is the panel's PHYSICAL resolution (Hyprland's w/h are already
        // physical pixels); scale is a SEPARATE arg. Never multiply them.
        Quickshell.execDetached(["hyprctl", "eval",
            `hl.monitor({ output = "${name}", mode = "${p.w}x${p.h}@${hz}", position = "${p.x}x${p.y}", scale = ${p.scale} })`])
        refreshLater.start()
    }
    function setScale(name, scale) {
        const p = panels.find(x => x.name === name)
        if (!p) return
        Quickshell.execDetached(["hyprctl", "eval",
            `hl.monitor({ output = "${name}", mode = "${p.w}x${p.h}@${p.refresh}", position = "${p.x}x${p.y}", scale = ${scale} })`])
        refreshLater.start()
    }
    Timer { id: refreshLater; interval: 700; onTriggered: root.refresh() }

    // ── hypridle (OLED burn-in protection) ──────────────────────────────
    function hypridleCheck() { if (!idleCheck.running) idleCheck.running = true }
    Process { id: idleCheck; command: ["bash", "-c", "pgrep -x hypridle >/dev/null && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: root.hypridleOn = this.text.trim() === "on" } }
    function setOledCare(on) {
        if (on) Quickshell.execDetached(["bash", "-lc", "pgrep -x hypridle >/dev/null || setsid hypridle >/dev/null 2>&1 &"])
        else    Quickshell.execDetached(["pkill", "-x", "hypridle"])
        root.hypridleOn = on
        careLater.start()
    }
    Timer { id: careLater; interval: 900; onTriggered: root.hypridleCheck() }

    // ── Projection (Super+P) ────────────────────────────────────────────
    function setProjection(mode) {
        // mode: "pc", "duplicate", "extend", "second"
        const intMon = panels.find(p => p.name.startsWith("eDP")) || panels[0]
        const extMon = panels.find(p => p.name !== intMon.name)
        if (!extMon) return // Nothing to project to
        
        let cmds = []
        if (mode === "pc") {
            cmds.push(`hl.monitor({ output = "${intMon.name}", mode = "${intMon.w}x${intMon.h}@${intMon.refresh}", position = "0x0", scale = ${intMon.scale} })`)
            cmds.push(`hl.monitor({ output = "${extMon.name}", disable = true })`)
        } else if (mode === "second") {
            cmds.push(`hl.monitor({ output = "${intMon.name}", disable = true })`)
            cmds.push(`hl.monitor({ output = "${extMon.name}", mode = "${extMon.w}x${extMon.h}@${extMon.refresh}", position = "0x0", scale = ${extMon.scale} })`)
        } else if (mode === "duplicate") {
            cmds.push(`hl.monitor({ output = "${intMon.name}", mode = "${intMon.w}x${intMon.h}@${intMon.refresh}", position = "0x0", scale = ${intMon.scale} })`)
            cmds.push(`hl.monitor({ output = "${extMon.name}", mode = "${extMon.w}x${extMon.h}@${extMon.refresh}", position = "0x0", scale = ${extMon.scale} })`)
        } else if (mode === "extend") {
            cmds.push(`hl.monitor({ output = "${intMon.name}", mode = "${intMon.w}x${intMon.h}@${intMon.refresh}", position = "0x0", scale = ${intMon.scale} })`)
            cmds.push(`hl.monitor({ output = "${extMon.name}", mode = "${extMon.w}x${extMon.h}@${extMon.refresh}", position = "auto-right", scale = ${extMon.scale} })`)
        }
        if (cmds.length) {
            Quickshell.execDetached(["hyprctl", "eval", cmds.join(" ")])
            refreshLater.start()
        }
    }

    Component.onCompleted: refresh()
}
