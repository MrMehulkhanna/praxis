pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// System updates, with the terminal taken out of the loop.
//
// praxis-update used to be launched inside a kitty window, which meant the
// one operation most likely to need explaining happened in a place with no
// affordances: no progress, no way to tell finished from stuck, and a
// reboot requirement buried in scrollback.
Singleton {
    id: root

    property bool   running:  false
    property bool   finished: false
    property bool   failed:   false
    property string phase:    ""          // the current ==> heading
    property var    lines:    []          // what has been printed so far
    property bool   restartNeeded: false
    property string restartReason: ""
    property string currentCommit:   ""
    property string latestCommit:    ""
    property var    incomingCommits: []
    property bool   upToDate:        true
    property bool   checking:        false

    readonly property string marker: "/var/lib/praxis/restart-required"

    function checkForUpdates() {
        if (!checkProc.running && !root.running) {
            root.checking = true
            checkProc.running = true
        }
    }

    Process {
        id: checkProc
        command: ["praxis-update", "--check-json"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.checking = false
                try {
                    const parsed = JSON.parse(this.text.trim())
                    root.currentCommit = parsed.current || ""
                    root.latestCommit = parsed.latest || parsed.current || ""
                    root.incomingCommits = Array.isArray(parsed.incoming) ? parsed.incoming : []
                    root.upToDate = parsed.upToDate !== undefined ? parsed.upToDate : (root.incomingCommits.length === 0)
                } catch (e) {
                    // ignore json parse error
                }
            }
        }
    }

    function checkRestart() { if (!restartProbe.running) restartProbe.running = true }
    Process {
        id: restartProbe
        command: ["bash", "-c", "cat /var/lib/praxis/restart-required 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim()
                root.restartNeeded = t !== ""
                root.restartReason = t
            }
        }
    }

    function start() {
        if (root.running) return
        root.running = true; root.finished = false; root.failed = false
        root.lines = []; root.phase = "starting"
        // Decide once, then run once. The obvious form —
        //   sudo -n praxis-update || praxis-update
        // can start the updater a second time while the first is still
        // going, and the two then deadlock on pacman's database lock: the
        // window sits on one phase forever with no error anywhere.
        proc.command = ["bash", "-c",
            // Ask whether *this command* may run passwordless — not `true`.
            // Installed PCs only allow praxis-update and a few tools, so
            // `sudo -n true` failed there, the update ran without admin
            // rights, and every step that writes to the system did nothing.
            "if sudo -n -l /usr/local/bin/praxis-update >/dev/null 2>&1; then exec sudo -n /usr/local/bin/praxis-update 2>&1; " +
            "else exec /usr/local/bin/praxis-update 2>&1; fi"]
        proc.running = true
    }

    function restartNow() { Quickshell.execDetached(["systemctl", "reboot"]) }
    function dismissRestart() {
        Quickshell.execDetached(["bash", "-c",
            "rm -f /var/lib/praxis/restart-required 2>/dev/null || sudo -n /usr/local/bin/praxis-update --dismiss-restart"])
        root.restartNeeded = false
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: line => {
                const clean = line.replace(/\x1b\[[0-9;]*m/g, "")
                if (clean.trim() === "") return
                // ==> is the script's own section heading; surfacing it as a
                // phase is what turns a wall of output into progress
                const h = clean.match(/^\s*==>\s*(.+)$/)
                if (h) root.phase = h[1].trim()
                const l = root.lines.slice()
                l.push(clean)
                if (l.length > 400) l.shift()
                root.lines = l
            }
        }
        onExited: code => {
            root.running = false
            root.finished = true
            root.failed = code !== 0
            root.phase = code === 0 ? "done" : "failed"
            root.checkRestart()
            root.checkForUpdates()
        }
    }

    Component.onCompleted: {
        checkRestart()
        checkForUpdates()
    }
}
