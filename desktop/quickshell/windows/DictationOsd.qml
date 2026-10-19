import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "root:/Config"
import "root:/Services"
import "root:/components"

// Voice typing indicator: a pill at the bottom of the focused screen while
// `praxis-dictate` listens or types. It follows the tool's state file, so it
// shows however dictation was started (Super+H, the terminal, a script).
// Click-through: it never takes the focus away from the window being typed into.
PanelWindow {
    id: osd
    screen: Shell.activeScreen
    anchors.bottom: true
    implicitWidth: pill.width + 40
    implicitHeight: pill.height + 60
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"
    mask: Region {}

    property string state: "idle"        // idle | listening | working
    property string mode: "text"         // text | command
    readonly property bool shown: state !== "idle"
    visible: shown || hideAnim.running

    readonly property string dir: Quickshell.env("XDG_RUNTIME_DIR") + "/praxis"
    // the file must exist before it can be watched
    Process {
        running: true
        command: ["bash", "-c", `mkdir -p "$1" && { [ -e "$1/dictate.state" ] || printf 'state=idle\\n' > "$1/dictate.state"; }`, "osd", osd.dir]
        onExited: stateFile.reload()
    }
    FileView {
        id: stateFile
        path: osd.dir + "/dictate.state"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const t = text()
            const get = (k, d) => { const m = t.match(new RegExp("^" + k + "=(.*)$", "m")); return m ? m[1] : d }
            osd.state = get("state", "idle")
            osd.mode = get("mode", "text")
        }
        onLoadFailed: osd.state = "idle"
    }

    Glass {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: osd.shown ? 34 : -height
        Behavior on anchors.bottomMargin { NumberAnimation { id: hideAnim; duration: Theme.normal; easing.type: Theme.easeMove } }
        opacity: osd.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        width: row.width + 28
        height: 44
        radius: 22
        color: Theme.glassStrong

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 10

            // pulsing mic while listening, spinning ring while working
            Item {
                width: 26; height: 26
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.centerIn: parent
                    width: 26; height: 26; radius: 13
                    color: osd.state === "listening" ? Theme.alpha(Theme.red, 0.22) : Theme.alpha(Theme.accent, 0.18)
                    SequentialAnimation on scale {
                        running: osd.state === "listening"; loops: Animation.Infinite
                        NumberAnimation { from: 0.85; to: 1.15; duration: 650; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.15; to: 0.85; duration: 650; easing.type: Easing.InOutSine }
                    }
                }
                Icon {
                    anchors.centerIn: parent
                    name: osd.state === "listening" ? "mic" : osd.mode === "command" ? "terminal" : "keyboard"
                    size: 14
                    color: osd.state === "listening" ? Theme.red : Theme.accent
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    text: osd.state === "listening"
                          ? (osd.mode === "command" ? "Listening for a command…" : "Listening…")
                          : (osd.mode === "command" ? "Writing the command…" : "Typing…")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold
                }
                Text {
                    visible: osd.state === "listening"
                    text: osd.mode === "command" ? "Super+Shift+H when done · it's typed, not run" : "Super+H when done · say “new line”, “press enter”"
                    color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs
                }
            }
        }
    }
}
