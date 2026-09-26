import QtQuick
import Quickshell
import Quickshell.Io
import "root:/Config"
import "root:/Services"
import "root:/components"

// Activity Center: what the AI and the machine are doing, as it happens.
// Live SSE feed from the backend + system stats. Nothing hidden.
OverlayWindow {
    id: win
    name: "activity"
    scrim: false
    grabKeyboard: false
    onOpened: { Sys.active++; feed.running = true; Aios.refreshWanted++; Aios.refresh(); hwProbe.running = true }
    onOpenChanged: if (!open) { Sys.active = Math.max(0, Sys.active - 1); feed.running = false; Aios.refreshWanted = Math.max(0, Aios.refreshWanted - 1) }

    readonly property ListModel events: ListModel {}
    property var hw: ({})

    property string activeView: "events"
    property var topList: []
    onActiveViewChanged: { if (activeView !== "events") { psProc.running = false; psProc.running = true; } }
    property var currentBuf: []
    Process {
        id: psProc
        command: ["bash", "-c", `
            MODE=$1
            if [ "$MODE" = "cpu" ] || [ "$MODE" = "mem" ]; then
                ps -eo pid,%cpu,%mem,rss,comm --sort=-%$MODE | head -n 11 | awk 'NR>1 {comm=""; for(i=5; i<=NF; i++) comm=comm $i " "; print $1"|"$2"|"$3"|"$4"|"comm}'
            elif [ "$MODE" = "gpu" ]; then
                nvidia-smi --query-compute-apps=pid,used_memory,process_name --format=csv,noheader | head -n 10 | awk -F', ' '{print $1"|||"$2"|"$3}'
            fi
        `, "--", win.activeView]
        stdout: SplitParser {
            onRead: line => win.currentBuf.push(line)
        }
        onExited: {
            if (win.activeView === "events") { win.currentBuf = []; return; }
            let list = [];
            for (let l of win.currentBuf) {
                if (!l || l.indexOf("|") === -1) continue;
                let p = l.split("|");
                list.push({
                    pid: p[0],
                    cpu: p[1] ? p[1] + "%" : "",
                    mem: p[2] ? p[2] + "%" : "",
                    rss: p[3] ? (p[3].includes("MiB") ? p[3] : (parseInt(p[3])/1024).toFixed(1) + "M") : "",
                    comm: p[4] ? p[4].replace(/^\s+|\s+$/g, "") : ""
                });
            }
            win.topList = list;
            win.currentBuf = [];
        }
    }
    Timer {
        running: win.activeView !== "events" && win.open
        interval: 1500; repeat: true; triggeredOnStart: true
        onTriggered: { psProc.running = false; psProc.running = true }
    }

    // live feed
    Process {
        id: feed
        command: ["curl", "-sN", Aios.base + "/api/activity/stream"]
        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: block => {
                const ev = Aios.parseSse(block)
                if (!ev) return
                let v; try { v = JSON.parse(ev.data) } catch (e) { return }
                if (ev.event === "jobs") { Aios.jobs = v; return }
                win.events.append({ ts: v.ts, job: v.job || "", stage: v.stage, msg: v.msg })
                while (win.events.count > 80) win.events.remove(0)
                list.positionViewAtEnd()
            }
        }
        onExited: if (win.open) restartFeed.start()
    }
    Timer { id: restartFeed; interval: 2000; onTriggered: feed.running = true }

    // initial backlog
    Process {
        id: backlog
        command: ["curl", "-sf", "-m", "3", Aios.base + "/api/activity?limit=40"]
        running: win.open
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const a = JSON.parse(this.text)
                    win.events.clear()
                    for (const v of a.events) win.events.append({ ts: v.ts, job: v.job || "", stage: v.stage, msg: v.msg })
                    Aios.jobs = a.jobs || []
                    list.positionViewAtEnd()
                } catch (e) {}
            }
        }
    }

    // hardware snapshot every 3 s while open
    Timer { interval: 3000; running: win.open; repeat: true; onTriggered: if (!hwProbe.running) hwProbe.running = true }
    Process {
        id: hwProbe
        command: ["curl", "-sf", "-m", "3", Aios.base + "/api/hardware"]
        stdout: StdioCollector { onStreamFinished: { try { win.hw = JSON.parse(this.text) } catch (e) {} } }
    }

    function stageColor(s) {
        switch (s) {
            case "error": case "refused": return Theme.red
            case "result": case "executed": return Theme.green
            case "approval": case "cancelled": return Theme.yellow
            case "routed": case "classified": case "generate": return Theme.accent
            case "gather": case "execute": return Theme.teal
            default: return Theme.muted
        }
    }
    function fmtB(n) { return n > 1048576 ? (n / 1048576).toFixed(1) + " MB/s" : n > 1024 ? (n / 1024).toFixed(0) + " KB/s" : Math.round(n) + " B/s" }

    Glass {
        id: card
        anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
        anchors.topMargin: Theme.barHeight + Theme.barMargin + 8
        anchors.bottomMargin: Theme.dockIcon + 16 + Theme.dockMargin + 12
        anchors.rightMargin: win.open ? Theme.barMargin : -(width + 24)
        Behavior on anchors.rightMargin { NumberAnimation { duration: Theme.slow; easing.type: Theme.easeMove } }
        width: 520
        radius: Theme.radiusXl
        color: Theme.glassStrong
        MouseArea { anchors.fill: parent }

        // ── header ──
        Item {
            id: header
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            height: 36
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 10
                Icon { name: "eye"; size: 18; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Activity"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontLg; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    visible: Aios.jobs.length > 0
                    height: 22; width: jt.width + 16; radius: 11; color: Theme.alpha(Theme.accent, 0.2); border.width: 1; border.color: Theme.alpha(Theme.accent, 0.5)
                    anchors.verticalCenter: parent.verticalCenter
                    Text { id: jt; anchors.centerIn: parent; text: Aios.jobs.length + " running"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs }
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4
                IconButton { icon: "trash"; iconSize: 13; onClicked: win.events.clear(); anchors.verticalCenter: parent.verticalCenter }
                IconButton { icon: "x"; iconSize: 14; onClicked: Shell.closeAll(); anchors.verticalCenter: parent.verticalCenter }
            }
        }

        // ── running jobs ──
        Column {
            id: jobsCol
            anchors { top: header.bottom; left: parent.left; right: parent.right; margins: 14; topMargin: 4 }
            spacing: 4
            Repeater {
                model: Aios.jobs
                Rectangle {
                    required property var modelData
                    width: jobsCol.width; height: 34; radius: Theme.radiusMd
                    color: Theme.alpha(Theme.accent, 0.10); border.width: 1; border.color: Theme.alpha(Theme.accent, 0.3)
                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Icon { name: "refresh"; size: 13; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter
                            RotationAnimation on rotation { loops: Animation.Infinite; from: 0; to: 360; duration: 1200 } }
                        Text { text: modelData.kind + " · " + modelData.stage + " · " + (modelData.mode || "") + " " + (modelData.model || ""); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.title; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; width: 200; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }

        // ── stats strip ──
        Rectangle {
            id: stats
            anchors { top: jobsCol.bottom; left: parent.left; right: parent.right; margins: 14; topMargin: 8 }
            height: 62; radius: Theme.radiusLg
            color: Theme.alpha(Theme.text, 0.05); border.width: 1; border.color: Theme.border
            readonly property var g: win.hw.gpu || ({})
            readonly property var m: win.hw.memory || ({})
            readonly property var c: win.hw.cpu || ({})
            Row {
                anchors.centerIn: parent
                spacing: 18
                Repeater {
                    model: [
                        { l: "CPU", v: Math.round(stats.c.usage || Sys.cpu) + "%", s: (stats.c.temp_c || Sys.cpuTempC) + "°C", p: (stats.c.usage || Sys.cpu) / 100, view: "cpu" },
                        { l: "RAM", v: (stats.m.used ? (stats.m.used / 1e9).toFixed(1) : Sys.memUsedGb.toFixed(1)) + " G", s: Math.round(stats.m.percent || Sys.mem) + "%", p: (stats.m.percent || Sys.mem) / 100, view: "mem" },
                        { l: "GPU", v: Math.round(stats.g.util || Sys.gpu) + "%", s: (stats.g.temp_c || Sys.gpuTempC) + "°C", p: (stats.g.util || Sys.gpu) / 100, view: "gpu" },
                        { l: "VRAM", v: ((stats.g.vram_used_mb || Sys.vramUsedGb * 1024) / 1024).toFixed(1) + " G", s: "of " + ((stats.g.vram_total_mb || 6141) / 1024).toFixed(0) + " G", p: (stats.g.vram_used_mb || Sys.vramUsedGb * 1024) / (stats.g.vram_total_mb || 6141), view: "gpu" },
                        { l: "NET", v: "↓" + win.fmtB(win.hw.network ? win.hw.network.down_bps : Sys.netDown), s: "↑" + win.fmtB(win.hw.network ? win.hw.network.up_bps : Sys.netUp), p: 0, view: "events" },
                    ]
                    Item {
                        width: 60; height: col.implicitHeight
                        Column {
                            id: col
                            spacing: 3
                            anchors.centerIn: parent
                            Text { text: modelData.l; color: Theme.muted; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.v; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: Theme.fontSm; font.weight: Font.Bold; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.s; color: Theme.text2; font.family: Theme.fontMono; font.pixelSize: 10; anchors.horizontalCenter: parent.horizontalCenter }
                            Rectangle { width: 60; height: 3; radius: 1.5; color: Theme.surface3; anchors.horizontalCenter: parent.horizontalCenter
                                Rectangle { width: parent.width * Math.max(0, Math.min(1, modelData.p)); height: 3; radius: 1.5; color: modelData.p > 0.85 ? Theme.red : modelData.p > 0.6 ? Theme.yellow : Theme.accent } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.activeView = (win.activeView === modelData.view) ? "events" : modelData.view
                        }
                    }
                }
            }
        }

        // ── pipeline feed ──
        ListView {
            id: list
            visible: win.activeView === "events"
            anchors { top: stats.bottom; left: parent.left; right: parent.right; bottom: footer.top; margins: 14; topMargin: 10; bottomMargin: 8 }
            model: win.events
            spacing: 2
            clip: true
            delegate: Item {
                required property var model
                width: list.width; height: 22
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text { text: Qt.formatTime(new Date(model.ts * 1000), "HH:mm:ss"); color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: 10; width: 56; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: 6; height: 6; radius: 3; color: win.stageColor(model.stage); anchors.verticalCenter: parent.verticalCenter }
                    Text { text: model.stage; color: win.stageColor(model.stage); font.family: Theme.fontMono; font.pixelSize: 10; width: 66; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: model.msg; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; width: list.width - 160; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            header: Item { width: list.width; height: win.events.count ? 0 : 60
                Text { anchors.centerIn: parent; visible: win.events.count === 0; text: "Waiting for activity — ask the AI something."; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontSm } }
        }

        // ── task manager view ──
        ListView {
            id: topView
            visible: win.activeView !== "events"
            anchors { top: stats.bottom; left: parent.left; right: parent.right; bottom: footer.top; margins: 14; topMargin: 10; bottomMargin: 8 }
            model: win.topList
            spacing: 2
            clip: true
            delegate: Item {
                required property var modelData
                width: topView.width; height: 22
                
                // Hover highlight
                Rectangle { anchors.fill: parent; radius: 4; color: hover.containsMouse ? Theme.hover : "transparent" }
                MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text { text: modelData.pid; color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: 10; width: 46; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData.cpu; color: Theme.accent; font.family: Theme.fontMono; font.pixelSize: 10; width: 40; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData.mem || modelData.rss; color: Theme.text2; font.family: Theme.fontMono; font.pixelSize: 10; width: 50; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData.comm; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs; elide: Text.ElideRight; width: topView.width - 184; anchors.verticalCenter: parent.verticalCenter }
                    IconButton { 
                        icon: "x"
                        iconSize: 12
                        opacity: hover.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        onClicked: Shell.run("kill -15 " + modelData.pid)
                        anchors.verticalCenter: parent.verticalCenter 
                    }
                }
            }
            header: Item { width: topView.width; height: 26
                Row {
                    spacing: 8; anchors.verticalCenter: parent.verticalCenter
                    Text { text: "PID"; color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: 10; width: 46; font.weight: Font.Bold }
                    Text { text: win.activeView === "gpu" ? "" : "CPU"; color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: 10; width: 40; font.weight: Font.Bold }
                    Text { text: win.activeView === "gpu" ? "VRAM" : "MEM"; color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: 10; width: 50; font.weight: Font.Bold }
                    Text { text: "PROCESS"; color: Theme.muted; font.family: Theme.font; font.pixelSize: 10; width: topView.width - 184; font.weight: Font.Bold }
                }
            }
        }

        // ── footer ──
        Row {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            height: 30
            spacing: 6
            IconButton { icon: "sparkle"; label: (Aios.loadedInfo ? Aios.loadedInfo.label + " in VRAM" : "no model loaded"); onClicked: Shell.open("ai") }
            IconButton { visible: Aios.loadedModel !== ""; icon: "gpu"; label: "Free VRAM"; onClicked: Aios.unload() }
            IconButton { icon: "terminal"; label: "ai logs -f"; onClicked: { Shell.run("kitty -e bash -lc 'ai logs -f'"); Shell.closeAll() } }
        }
    }
}
