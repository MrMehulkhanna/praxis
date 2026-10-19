pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "root:/Config"

// Wallpapers: stills (hyprpaper) and live videos (mpvpaper), both driven
// through `praxis-wallpaper`, which keeps the choice in
// ~/.config/praxis/wallpaper.state. This service lists what's available,
// mirrors that state for the Settings window, restores it at login, repairs
// the live wallpaper when a monitor is plugged in, and — unless the user opts
// out — shows the still image instead of the video while on battery.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/share/wallpapers"
    readonly property string thumbDir: Quickshell.env("HOME") + "/.cache/praxis/wallpaper-thumbs"
    readonly property string stateFile: Quickshell.env("HOME") + "/.config/praxis/wallpaper.state"

    property var files: []            // still images
    property var videos: []           // [{ path, thumb }] — only ones ffmpeg could read
    property bool liveSupported: false

    // mirrored from the state file
    property string mode: "still"
    property string still: ""
    property string live: ""
    readonly property bool isLive: mode === "live" && live !== ""
    // may the video play right now? (on battery only if the user allows it)
    readonly property bool liveAllowed: !UPower.onBattery || Settings.liveOnBattery
    readonly property bool liveSuspended: isLive && !liveAllowed
    readonly property string current: isLive ? live : (still || Settings.wallpaper)

    function refresh() { if (!scan.running) scan.running = true }
    Process {
        id: scan
        command: ["bash", "-c", `
            d=$1 t=$2; mkdir -p "$d" "$t"
            command -v mpvpaper >/dev/null && echo M
            find "$d" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) | sort | sed 's/^/S\\t/'
            find "$d" -maxdepth 2 -type f \\( -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \\) | sort |
            while IFS= read -r v; do
                th="$t/$(printf '%s' "$v" | md5sum | cut -c1-16).jpg"
                if [ ! -s "$th" ] || [ "$v" -nt "$th" ]; then
                    ffmpeg -v error -y -ss 1 -i "$v" -frames:v 1 -vf scale=400:-2 "$th" </dev/null >/dev/null 2>&1 || rm -f "$th"
                fi
                [ -s "$th" ] && printf 'L\\t%s\\t%s\\n' "$v" "$th"
            done`, "wallpaper-scan", root.dir, root.thumbDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const stills = [], vids = []
                let mpv = false
                for (const line of this.text.split("\n")) {
                    const f = line.split("\t")
                    if (f[0] === "M") mpv = true
                    else if (f[0] === "S" && f[1]) stills.push(f[1])
                    else if (f[0] === "L" && f[1]) vids.push({ path: f[1], thumb: f[2] || "" })
                }
                root.files = stills
                root.videos = vids
                root.liveSupported = mpv
            }
        }
    }

    FileView {
        id: stateView
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseState(text())
        onLoadFailed: root.parseState("")
    }
    function parseState(t) {
        const get = k => { const m = t.match(new RegExp("^" + k + "=(.*)$", "m")); return m ? m[1] : "" }
        root.live = get("live")
        root.still = get("still")
        root.mode = get("mode") || (root.live ? "live" : "still")
    }

    // ── actions ────────────────────────────────────────────────────────────
    function apply(path) {                       // still image
        if (!path) return
        Settings.wallpaper = path
        run(["still", path])
    }
    function applyLive(path) {
        if (!path) return
        if (liveAllowed) { run(["live", path]); return }
        run(["live", path, "--save-only"])
        Notifs.notify("Live wallpaper saved", "You're on battery, so the still image stays for now — the video plays when you plug in. (Settings › Wallpaper › Play on battery)")
    }
    function stopLive() { run(["stop"]) }

    property var queued: null
    function run(args) {
        if (cmd.running) { queued = args; return }
        cmd.command = ["praxis-wallpaper"].concat(args)
        cmd.running = true
    }
    Process {
        id: cmd
        stderr: StdioCollector { id: cmdErr }
        onExited: code => {
            stateView.reload()
            if (code !== 0 && cmdErr.text.trim()) Notifs.notify("Wallpaper", cmdErr.text.trim())
            if (root.queued) { const next = root.queued; root.queued = null; root.run(next) }
        }
    }

    // ── login: once settings are known, put the saved wallpaper back ───────
    // (a still chosen before the state file existed is carried over once)
    property bool started: false
    function start() {
        if (started || !Settings.ready) return
        started = true
        startProc.command = ["bash", "-c",
            `s=$1 f=$2
             if [ -n "$s" ] && ! grep -qs '^still=' "$f"; then mkdir -p "$(dirname "$f")"; echo "still=$s" >> "$f"; fi
             exec praxis-wallpaper "$3"`, "wallpaper-start", Settings.wallpaper, root.stateFile, root.liveAllowed ? "restore" : "suspend"]
        startProc.running = true
    }
    Process { id: startProc; onExited: stateView.reload() }
    Connections { target: Settings; function onReadyChanged() { root.start() } }

    // a monitor that appears later gets the live wallpaper too
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "monitoradded" || event.name === "monitoraddedv2") hotplug.restart()
        }
    }
    Timer { id: hotplug; interval: 2000; onTriggered: root.sync() }

    // plugging in / unplugging the charger switches video <-> still
    function sync() { if (root.isLive) root.run([root.liveAllowed ? "restore" : "suspend"]) }
    onLiveAllowedChanged: if (started) sync()

    IpcHandler {
        target: "wallpaper"
        function set(path: string): void { root.apply(path) }
        function live(path: string): void { root.applyLive(path) }
        function stop(): void { root.stopLive() }
    }

    Component.onCompleted: { refresh(); start() }
}
