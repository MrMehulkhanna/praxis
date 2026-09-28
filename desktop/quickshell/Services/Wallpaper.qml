pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/Config"

// Wallpapers via hyprpaper. Choice is persisted in Settings and re-applied
// on every shell start; hyprpaper.conf is regenerated so it survives reboot.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/share/wallpapers"
    readonly property string conf: Quickshell.env("HOME") + "/.config/hypr/hyprpaper.conf"
    property var files: []

    function refresh() { if (!scan.running) scan.running = true }
    Process {
        id: scan
        command: ["bash", "-c", `mkdir -p "${root.dir}"; find "${root.dir}" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) | sort`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.files = this.text.trim().split("\n").filter(f => f)
                // Fresh account: no wallpaper chosen yet. Apply a default so
                // hyprpaper.conf gets absolute paths instead of relying on the
                // shipped template (which uses ~).
                if (!Settings.wallpaper && root.files.length) {
                    root.apply(root.files.find(f => f.endsWith("/deep-purple.png")) || root.files[0])
                }
            }
        }
    }

    function apply(path) {
        if (!path) return
        Settings.wallpaper = path
        applyProc.command = ["bash", "-c",
            `cat > "${root.conf}" <<EOF\nipc = on\nsplash = false\npreload = ${path}\nwallpaper = ,${path}\nEOF\n` +
            `pgrep -x hyprpaper >/dev/null || (setsid hyprpaper >/dev/null 2>&1 & sleep 1.2); ` +
            `hyprctl hyprpaper preload "${path}" >/dev/null; hyprctl hyprpaper wallpaper ",${path}" >/dev/null; ` +
            `sleep 0.5; hyprctl hyprpaper unload unused >/dev/null 2>&1; true`]
        applyProc.running = true
    }
    Process { id: applyProc }

    IpcHandler { target: "wallpaper"; function set(path: string): void { root.apply(path) } }

    Component.onCompleted: {
        refresh()
        if (Settings.wallpaper) apply(Settings.wallpaper)
    }
}
