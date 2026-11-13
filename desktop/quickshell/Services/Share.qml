pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Screen sharing between two Praxis machines — the state behind ShareWindow.
//
// Everything real happens in praxis-share; this watches it and drives it, so
// the window and the CLI can never disagree about what is running.
Singleton {
    id: root

    property bool  serving:     false
    property int   port:        5920
    property string servingMon: ""      // the virtual display being sent, if any
    property string localIp:    ""
    property bool   withAudio:  true
    property string mode:       "extend"   // extend | mirror
    property string mirrorOf:   ""
    property bool   ready:      false      // praxis-share doctor is happy
    property string blockedBy:  ""         // what is missing, if anything
    property string pairCode:   ""         // shown by the host, typed on the viewer
    property var    nearbyHosts: []        // auto-discovered machines sharing on local Wi-Fi
    property bool   scanning:    false

    // live figures, so the UI can show what is actually happening rather
    // than what we hope is happening
    property int   kbps:       0
    property int   clients:    0
    property string vcodec:    ""
    property string resolution: ""

    readonly property var displays: Hyprland.monitors.values
    readonly property int displayCount: displays.length

    // ── polling ────────────────────────────────────────────────────────
    function refresh() {
        if (!statusProc.running) statusProc.running = true
        root.scan()
    }

    function scan() {
        if (!scanProc.running) {
            root.scanning = true
            scanProc.running = true
        }
    }

    Timer {
        id: scanTimer
        interval: 3500
        running: true; repeat: true
        onTriggered: root.scan()
    }

    Process {
        id: scanProc
        command: ["praxis-share-gate", "scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false
                try {
                    const parsed = JSON.parse(this.text.trim())
                    if (Array.isArray(parsed)) root.nearbyHosts = parsed.filter(d => !d.is_self)
                } catch (e) {
                    // ignore json error
                }
            }
        }
    }
    Timer {
        interval: root.serving ? 2000 : 8000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        // No ${...} anywhere in here: this is a JS template literal, so the
        // shell's brace expansion would be eaten by JavaScript before bash
        // ever saw it. Plain $VAR only.
        command: ["bash", "-c", `
S="$XDG_RUNTIME_DIR/praxis-share"
[ -n "$XDG_RUNTIME_DIR" ] || S="/run/user/$(id -u)/praxis-share"
GATE="$S/gate.pid"
PID="$S/capture.pid"
if ([ -f "$GATE" ] && kill -0 "$(cat "$GATE")" 2>/dev/null) || ([ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null); then
  PORT="$(cat "$S/port" 2>/dev/null)"
  echo "serving=1"
  echo "port=$PORT"
  echo "monitor=$(cat "$S/monitor" 2>/dev/null)"
  CLIENTS=0
  if [ -s "$S/clients.json" ]; then
    CLIENTS=$(python3 -c "import json; print(json.load(open('$S/clients.json')).get('count',0))" 2>/dev/null || echo 0)
  else
    CLIENTS=$(ss -tn state established 2>/dev/null | grep -c ":$PORT" || echo 0)
  fi
  echo "clients=$CLIENTS"
  echo "code=$(cat "$S/code" 2>/dev/null)"
else
  echo "serving=0"
fi
echo "ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
if [ -f "$S/viewer.pids" ] && kill -0 "$(awk '{print $1}' "$S/viewer.pids" 2>/dev/null)" 2>/dev/null; then
  echo "viewing=1"
  echo "viewTarget=$(cat "$S/viewer.target" 2>/dev/null)"
fi
if [ -f "$S/input.pid" ] && kill -0 "$(cat "$S/input.pid")" 2>/dev/null; then
  echo "inputSharing=1"
else
  echo "inputSharing=0"
fi
`]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {}
                for (const l of this.text.trim().split("\n")) {
                    const i = l.indexOf("=")
                    if (i > 0) kv[l.slice(0, i)] = l.slice(i + 1)
                }
                root.serving    = kv.serving === "1"
                root.localIp    = kv.ip || ""
                if (root.serving) {
                    root.port       = parseInt(kv.port) || root.port
                    root.servingMon = kv.monitor || ""
                    root.clients    = parseInt(kv.clients) || 0
                    root.pairCode   = kv.code || ""
                } else {
                    root.servingMon = ""; root.clients = 0; root.pairCode = ""
                }
                if (kv.viewing === "1") {
                    root.viewing = true
                    if (kv.viewTarget) root.viewTarget = kv.viewTarget
                } else if (!viewer.running) {
                    root.viewing = false
                }
                root.inputSharing = kv.inputSharing === "1"
            }
        }
    }

    // ── readiness ──────────────────────────────────────────────────────
    function checkReady() { if (!doctorProc.running) doctorProc.running = true }
    Process {
        id: doctorProc
        command: ["bash", "-c", "praxis-share doctor 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const missing = []
                for (const l of this.text.split("\n")) {
                    const m = l.match(/^\s*✗\s+(.+?)\s{2,}/)
                    if (m) missing.push(m[1].trim())
                }
                root.blockedBy = missing.join(", ")
                root.ready = missing.length === 0
            }
        }
    }

    // ── actions ────────────────────────────────────────────────────────
    function start() {
        const args = ["praxis-share", root.mode === "mirror" ? "mirror" : "extend",
                      "--port", String(root.port)]
        if (root.mode === "mirror" && root.mirrorOf) { args.push("--output"); args.push(root.mirrorOf) }
        if (!root.withAudio) args.push("--no-audio")
        act.command = args
        act.running = true
    }
    function stop() { act.command = ["praxis-share", "stop"]; act.running = true }
    // ── viewing someone else's screen ─────────────────────────────────
    // A Process we own, not a terminal: the window knows when the viewer is
    // up, can show what it is connected to, and can end it.
    property bool   viewing:      false
    property string viewTarget:   ""
    property string connectError: ""
    property bool   inputControl: false
    property bool   inputSharing: false

    function connectTo(target, code) {
        if (viewer.running) return
        root.connectError = ""
        root.viewTarget = target
        if (root.inputControl) {
            const hostOnly = target.split(":")[0]
            if (hostOnly) root.joinInput(hostOnly)
        }
        viewer.command = ["praxis-share", "connect", target, "--code", code]
        viewer.running = true
    }
    function disconnect() {
        Quickshell.execDetached(["praxis-share", "disconnect"])
        if (root.inputSharing) root.stopInput()
        viewer.running = false
        root.viewing = false
        soon.start()
    }
    function startInput(peer) {
        Quickshell.execDetached(["praxis-share", "input", "host", "--peer", peer || "praxis-peer"])
    }
    function joinInput(host) {
        Quickshell.execDetached(["praxis-share", "input", "join", host])
    }
    function stopInput() {
        Quickshell.execDetached(["praxis-share", "input", "stop"])
    }
    Process {
        id: viewer
        onRunningChanged: root.viewing = running
        stderr: StdioCollector {
            onStreamFinished: {
                const t = this.text.replace(/\x1b\[[0-9;]*m/g, "").trim()
                if (t.indexOf("not accepted") >= 0) root.connectError = "Wrong code — check the four digits on the other PC."
                else if (t.indexOf("cannot reach") >= 0) root.connectError = "Cannot reach that PC. Is it still sharing, on the same Wi-Fi?"
                else if (t.indexOf("viewer stopped") >= 0) root.connectError = "The picture stopped. Run praxis-share doctor on this PC."
            }
        }
        onExited: {
            if (root.inputSharing) root.stopInput()
            soon.start()
        }
    }

    // ── controlling the shared display, as the host ────────────────────
    function sendWindowThere() {
        const mon = root.servingMon || "HEADLESS-1"
        Quickshell.execDetached(["hyprctl", "dispatch",
            'hl.dsp.window.move({ monitor = "' + mon + '" })'])
    }
    function bringBack() { Quickshell.execDetached(["praxis-share", "bring-back"]) }

    Process {
        id: act
        stderr: StdioCollector { onStreamFinished: if (this.text.trim()) console.warn("praxis-share:", this.text.trim()) }
        onExited: soon.start()
    }
    Timer { id: soon; interval: 700; onTriggered: root.refresh() }

    Component.onCompleted: { refresh(); checkReady() }
}
