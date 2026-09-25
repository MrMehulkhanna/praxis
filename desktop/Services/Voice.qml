pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Push-to-talk bridge. startListening() records, stopListening() runs the
// transcribe → security gate → (execute | ask AIOS) → speak pipeline and
// prints one JSON line we parse. Event-driven off process exit.
Singleton {
    id: root

    property bool listening: false
    property bool processing: false
    property string lastTranscript: ""
    property string lastReply: ""
    property string lastKind: ""   // command | confirm_pending | refused | question | empty | error
    property bool lastExecuted: false

    readonly property string home: Quickshell.env("HOME")

    function startListening() {
        if (listening || processing) return
        listening = true
        lastReply = ""
        startProc.command = ["bash", "-lc", `${home}/aios/voice/voice_start.sh`]
        startProc.running = true
    }
    function stopListening() {
        if (!listening) return
        listening = false
        processing = true
        stopProc.command = ["bash", "-lc",
            `${home}/aios/.venv/bin/python3 ${home}/aios/voice/voice_stop_and_process.py`]
        stopProc.running = true
    }

    Process { id: startProc }
    Process {
        id: stopProc
        stdout: SplitParser {
            onRead: line => {
                if (!line.trim()) return
                try {
                    const r = JSON.parse(line)
                    root.lastTranscript = r.transcript || ""
                    root.lastKind = r.kind || ""
                    root.lastExecuted = !!r.executed
                    root.lastReply = r.reply || ""
                } catch (e) {
                    root.lastKind = "error"
                    root.lastReply = "Couldn't parse voice pipeline output"
                }
                root.processing = false
            }
        }
        onExited: (code, status) => { root.processing = false }
    }
}
