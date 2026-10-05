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

    // ── modes, refresh rate, scale: through praxis-display ──────────────
    // A change applies at once and goes back by itself after 15 s unless kept
    // (Settings shows "Keep these display settings?") — a mode the monitor
    // can't show never leaves it dark. Kept changes survive a restart.
    function setMode(name, mode, scale) {
        Quickshell.execDetached(["praxis-display", "set", name, mode].concat(scale !== undefined ? [String(scale)] : []))
        pendingPoll.restart(); refreshLater.start()
    }
    function setRefresh(name, hz) {
        const p = panels.find(x => x.name === name)
        if (!p) return
        const m = (p.modes || []).find(md => md.startsWith(`${p.w}x${p.h}@`) && Math.abs(parseFloat(md.split("@")[1]) - hz) < 0.6)
        setMode(name, m ? m.replace("Hz", "") : `${p.w}x${p.h}@${hz}`)
    }
    function setScale(name, scale) {
        const p = panels.find(x => x.name === name)
        if (!p) return
        setMode(name, `${p.w}x${p.h}@${p.refresh}`, scale)
    }
    // refresh rates this panel offers at its current resolution, e.g. [60, 120] or [60, 144, 165]
    function ratesOf(p) {
        if (!p) return []
        const rates = (p.modes || []).filter(m => m.startsWith(`${p.w}x${p.h}@`)).map(m => Math.round(parseFloat(m.split("@")[1])))
        return [...new Set(rates)].sort((a, b) => a - b)
    }
    property var pending: ({ pending: false })
    function keep()   { Quickshell.execDetached(["praxis-display", "keep"]); pending = { pending: false }; refreshLater.start() }
    function revert() { Quickshell.execDetached(["praxis-display", "revert"]); pending = { pending: false }; refreshLater.start() }
    property bool _sawPending: false
    property int _polls: 0
    Process {
        id: pendingProc
        command: ["praxis-display", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.pending = JSON.parse(this.text) } catch (e) { return }
                if (root.pending.pending) root._sawPending = true
                else if (root._sawPending || root._polls <= 0) { pendingPoll.stop(); root._sawPending = false }
            }
        }
    }
    // polls only while a change waits to be kept (or for 20 s after one was made)
    Timer {
        id: pendingPoll; interval: 1000; repeat: true
        onRunningChanged: if (running) { root._polls = 20; root._sawPending = false }
        onTriggered: { root._polls--; if (!pendingProc.running) pendingProc.running = true }
    }
    Timer { id: refreshLater; interval: 700; onTriggered: root.refresh() }

    // ── idle: dim, lock, (screen off), suspend on battery — via hypridle ──
    // oled: never blanks the panel (hypridle.conf); screenoff: turns screens
    // off too (hypridle-screenoff.conf). Kept in Settings, restored at login.
    readonly property string idleConf: Quickshell.env("HOME") + "/.config/hypr/" + (Settings.idleMode === "screenoff" ? "hypridle-screenoff.conf" : "hypridle.conf")
    function hypridleCheck() { if (!idleCheck.running) idleCheck.running = true }
    Process { id: idleCheck; command: ["bash", "-c", "pgrep -x hypridle >/dev/null && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: root.hypridleOn = this.text.trim() === "on" } }
    function setIdle(mode) {                  // off | oled | screenoff
        Settings.idleMode = mode
        applyIdle()
    }
    function applyIdle() {
        const m = Settings.idleMode
        if (m === "") return                 // never chosen: leave whatever runs alone
        if (m === "off") Quickshell.execDetached(["pkill", "-x", "hypridle"])
        else Quickshell.execDetached(["bash", "-c", 'pkill -x hypridle; sleep 0.3; setsid hypridle -c "$1" >/dev/null 2>&1 &', "idle", root.idleConf])
        root.hypridleOn = m !== "off"
        careLater.start()
    }
    function setOledCare(on) { setIdle(on ? "oled" : "off") }
    Connections { target: Settings; function onReadyChanged() { if (Settings.ready) root.applyIdle() } }
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
