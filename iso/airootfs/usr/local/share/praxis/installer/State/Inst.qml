pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Installer state and actions. Everything that touches a disk is done by
// praxis-install-engine (as root, through the live session's sudo); this only
// gathers the answers, previews them and shows progress.
Singleton {
    id: s

    // ── machine ────────────────────────────────────────────────────────
    property var probe: null
    property bool probing: false
    property string probeError: ""
    property bool online: false
    readonly property var disks: probe ? probe.disks.filter(d => !d.is_live) : []
    readonly property string engineBin: Quickshell.env("PRAXIS_ENGINE") || "/usr/local/bin/praxis-install-engine"
    readonly property string libDir: Quickshell.env("PRAXIS_LIB") || "/usr/local/lib/praxis"

    function scan() {
        if (probeProc.running) return
        probing = true; probeError = ""
        probeProc.running = true
    }
    Process {
        id: probeProc
        command: ["sudo", "-n", "env", "PRAXIS_LIB=" + s.libDir, s.engineBin, "--probe"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    s.probe = JSON.parse(this.text)
                    if (s.diskIndex >= s.disks.length) s.diskIndex = 0
                    s.pickDefaultMode()
                } catch (e) { s.probeError = "Couldn't read the disks." }
                s.probing = false
            }
        }
        stderr: StdioCollector { onStreamFinished: if (this.text.trim() && !s.probe) s.probeError = this.text.trim() }
    }

    Process {
        id: netProc
        command: ["bash", "-c", "timeout 4 curl -sI https://archlinux.org >/dev/null"]
        onExited: code => s.online = code === 0
    }
    Timer { interval: 5000; running: s.stage === "idle"; repeat: true; triggeredOnStart: true; onTriggered: if (!netProc.running) netProc.running = true }

    // ── choices ────────────────────────────────────────────────────────
    property int diskIndex: 0
    readonly property var disk: disks.length ? disks[Math.min(diskIndex, disks.length - 1)] : null
    property string mode: ""                      // alongside | free | partition | wipe
    property real praxisGiB: 60
    property string targetPart: ""
    property string fs: "btrfs"
    property bool wipeConfirmed: false

    function opt(m) { return disk && disk.options[m] ? disk.options[m] : { possible: false, reason: "" } }
    function pickDefaultMode() {
        if (!disk) { mode = ""; return }
        for (const m of ["alongside", "free", "partition", "wipe"]) {
            if (opt(m).possible) { setMode(m); return }
        }
        mode = ""
    }
    function setMode(m) {
        mode = m; wipeConfirmed = false
        if (m === "alongside") praxisGiB = Math.round(opt("alongside").default_praxis_mib / 1024)
        if (m === "partition") targetPart = opt("partition").candidates[0] || ""
    }
    onDiskIndexChanged: pickDefaultMode()
    readonly property bool diskReady: !!disk && mode !== "" && opt(mode).possible && (mode !== "wipe" || wipeConfirmed)
                                      && (mode !== "partition" || targetPart !== "")

    // apps
    property var bundles: []                      // [{id, title, desc, pkgs}]
    property var apps: []
    function toggleApp(id) {
        const a = apps.slice(); const i = a.indexOf(id)
        if (i >= 0) a.splice(i, 1); else a.push(id)
        apps = a
    }
    Process {
        running: true
        command: ["bash", "-c", ". \"$1\"/install-common.sh && praxis_app_bundles", "bundles", s.libDir]
        stdout: StdioCollector {
            onStreamFinished: s.bundles = this.text.trim().split("\n").filter(l => l).map(l => {
                const f = l.split("|"); return { id: f[0], title: f[1], desc: f[2], pkgs: f[3] }
            })
        }
    }

    // you
    property string fullName: ""
    property string userName: ""
    property bool userEdited: false
    property string password: ""
    property string password2: ""
    property string hostName: ""
    property bool hostEdited: false
    property string timezone: "UTC"
    property string xkb: "us"
    property string locale: "en_US.UTF-8"
    property bool lockAtStart: true
    onFullNameChanged: {
        if (!userEdited) userName = (fullName.split(" ")[0] || "").toLowerCase().replace(/[^a-z0-9_-]/g, "")
    }
    onUserNameChanged: if (!hostEdited) hostName = userName ? userName + "-praxis" : ""
    readonly property string userError:
        !userName ? "" : !/^[a-z_][a-z0-9_-]{0,31}$/.test(userName) ? "lowercase letters, digits, - and _ — starting with a letter"
        : ["root", "praxis", "bin", "daemon", "nobody", "git", "http"].indexOf(userName) >= 0 ? "that name is reserved" : ""
    readonly property string passError: password && password.length < 4 ? "at least 4 characters" : password2 && password !== password2 ? "the two passwords don't match" : ""
    readonly property string hostError: hostName && !/^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(hostName) ? "letters, digits and - only" : ""
    readonly property bool youReady: fullName.trim() !== "" && !/[:,=]/.test(fullName) && userName !== "" && !userError
                                     && password.length >= 4 && password === password2 && hostName !== "" && !hostError
                                     && timezones.indexOf(timezone) >= 0

    property var timezones: []
    property var layouts: []
    property var locales: []
    Process {
        running: true
        command: ["bash", "-c", "timedatectl list-timezones 2>/dev/null || (cd /usr/share/zoneinfo && find . -type f | sed 's|^./||' | grep '/' | sort)"]
        stdout: StdioCollector { onStreamFinished: s.timezones = this.text.trim().split("\n") }
    }
    Process {
        running: true
        command: ["bash", "-c", "localectl list-x11-keymap-layouts 2>/dev/null || echo us"]
        stdout: StdioCollector { onStreamFinished: s.layouts = this.text.trim().split("\n") }
    }
    Process {
        running: true
        command: ["bash", "-c", "sed -n 's/^#\\?\\([a-zA-Z_@]*\\.UTF-8\\) UTF-8.*/\\1/p' /etc/locale.gen | sort -u"]
        stdout: StdioCollector { onStreamFinished: s.locales = this.text.trim().split("\n") }
    }
    Process {        // a time zone guess from the network (only a default — you can change it)
        id: tzGuess
        running: true
        command: ["bash", "-c", "curl -fsm 4 https://ipapi.co/timezone"]
        stdout: StdioCollector { onStreamFinished: { const t = this.text.trim(); if (t && t.indexOf("/") > 0 && s.timezone === "UTC") s.timezone = t } }
    }

    // ── install ────────────────────────────────────────────────────────
    property string stage: "idle"                 // idle | running | done | failed
    property int percent: 0
    property string stepText: ""
    property string failText: ""
    readonly property string planPath: Quickshell.env("XDG_RUNTIME_DIR") + "/praxis-install.plan"

    function install() {
        if (stage === "running") return
        stage = "running"; percent = 0; stepText = "Preparing"; failText = ""
        hashProc.environment = { PW: password }
        hashProc.running = true
    }
    Process {
        id: hashProc
        command: ["bash", "-c", "printf '%s' \"$PW\" | openssl passwd -6 -stdin"]
        stdout: StdioCollector {
            onStreamFinished: {
                const h = this.text.trim()
                if (!h.startsWith("$")) { s.stage = "failed"; s.failText = "Couldn't prepare the password."; return }
                const lines = [
                    "DISK=" + s.disk.path, "MODE=" + s.mode, "FS=" + s.fs,
                    s.mode === "alongside" ? "SHRINK_PART=" + s.opt("alongside").part : "",
                    s.mode === "alongside" ? "PRAXIS_MIB=" + Math.round(s.praxisGiB * 1024) : "",
                    s.mode === "partition" ? "TARGET_PART=" + s.targetPart : "",
                    "HOSTNAME=" + s.hostName, "USERNAME=" + s.userName, "FULLNAME=" + s.fullName.trim(),
                    "PASSWORD_HASH='" + h + "'",
                    "TIMEZONE=" + s.timezone, "LOCALE=" + s.locale, "KEYMAP=us", "XKB_LAYOUT=" + s.xkb,
                    "LOGIN=" + (s.lockAtStart ? "lock" : "auto"), "APPS=" + s.apps.join(" ")
                ].filter(l => l !== "")
                planProc.environment = { PLAN_TEXT: lines.join("\n") + "\n", PLAN_PATH: s.planPath }
                planProc.running = true
            }
        }
    }
    Process {
        id: planProc
        command: ["bash", "-c", "umask 077 && printf '%s' \"$PLAN_TEXT\" > \"$PLAN_PATH\""]
        onExited: code => {
            if (code !== 0) { s.stage = "failed"; s.failText = "Couldn't write the install plan."; return }
            engine.running = true
        }
    }
    // The engine runs detached (setsid): closing this window never stops an
    // installation half-way. Progress comes from its output file; reopening the
    // installer during an install shows that install's progress.
    readonly property string progressFile: Quickshell.env("XDG_RUNTIME_DIR") + "/praxis-install.progress"
    Process {
        id: engine
        command: ["bash", "-c", ": > \"$4\"; sudo -n env \"PRAXIS_LIB=$2\" setsid -f \"$3\" \"$1\" >>\"$4\" 2>&1",
                  "engine", s.planPath, s.libDir, s.engineBin, s.progressFile]
        onExited: watch.start()
    }
    Process {
        id: poll
        // last progress line, and whether the engine is still running
        command: ["bash", "-c", "grep '^@@ ' \"$1\" 2>/dev/null | tail -n1; p=$(cat /run/praxis-install.pid 2>/dev/null); [ -n \"$p\" ] && [ -d /proc/$p ] && echo RUNNING", "poll", s.progressFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n")
                const running = lines.indexOf("RUNNING") >= 0
                const last = lines.find(l => l.startsWith("@@ ")) || ""
                const f = last.match(/^@@ FAIL (.*)$/)
                const m = last.match(/^@@ (\d+) (.*)$/)
                if (m) { s.percent = parseInt(m[1]); s.stepText = m[2] }
                if (f) { s.failText = f[1]; s.stage = "failed"; watch.stop() }
                else if (s.percent === 100) { s.stage = "done"; watch.stop(); Quickshell.execDetached(["rm", "-f", s.planPath]) }
                else if (!running && s.stage === "running" && watch.ticks > 5) {
                    s.stage = "failed"; s.failText = s.failText || "The installer stopped unexpectedly."; watch.stop()
                } else if (running && s.stage === "idle") s.stage = "running"       // an install started before this window
            }
        }
    }
    Timer {
        id: watch
        property int ticks: 0
        interval: 1000; repeat: true
        onRunningChanged: if (running) ticks = 0
        onTriggered: { ticks++; if (!poll.running) poll.running = true }
    }
    // reopened during an installation: pick it up
    Process {
        running: true
        command: ["bash", "-c", "p=$(cat /run/praxis-install.pid 2>/dev/null); [ -n \"$p\" ] && [ -d /proc/$p ]"]
        onExited: code => { if (code === 0) { s.stage = "running"; s.resumed = true; watch.start() } }
    }
    property bool resumed: false

    Component.onCompleted: scan()
}
