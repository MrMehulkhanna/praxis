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

    // live figures, so the UI can show what is actually happening rather
    // than what we hope is happening
    property int   kbps:       0
    property int   clients:    0
    property string vcodec:    ""
    property string resolution: ""

    readonly property var displays: Hyprland.monitors.values
    readonly property int displayCount: displays.length

    // ── polling ────────────────────────────────────────────────────────
    function refresh() { if (!statusProc.running) statusProc.running = true }
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
PID="$S/capture.pid"
if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  PORT="$(cat "$S/port" 2>/dev/null)"
  echo "serving=1"
  echo "port=$PORT"
  echo "monitor=$(cat "$S/monitor" 2>/dev/null)"
  echo "clients=$(ss -tn state established 2>/dev/null | grep -c ":$PORT")"
else
  echo "serving=0"
fi
echo "ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
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
                } else {
                    root.servingMon = ""; root.clients = 0
                }
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
    function connectTo(target) { Quickshell.execDetached(["praxis-share", "connect", target]) }

    Process {
        id: act
        stderr: StdioCollector { onStreamFinished: if (this.text.trim()) console.warn("praxis-share:", this.text.trim()) }
        onExited: soon.start()
    }
    Timer { id: soon; interval: 700; onTriggered: root.refresh() }

    Component.onCompleted: { refresh(); checkReady() }
}
