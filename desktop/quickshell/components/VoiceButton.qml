import QtQuick
import Quickshell
import Quickshell.Io
import "root:/Config"
import "root:/Services"

// Voice typing button in the bar (praxis-dictate / Super+H).
// Click = start listening; click again = stop and type into focused window.
Item {
    id: root
    implicitWidth: 28; implicitHeight: 28

    property string state: "idle"       // idle | listening | working
    property string mode: "text"        // text | command

    readonly property string dir: Quickshell.env("XDG_RUNTIME_DIR") + "/praxis"

    // Ensure state file exists before FileView tries to watch it.
    // Without this init, watchChanges silently fails on a missing file.
    Process {
        running: true
        command: ["bash", "-c", `mkdir -p "$1" && { [ -e "$1/dictate.state" ] || printf 'state=idle\n' > "$1/dictate.state"; }`, "vb", root.dir]
        onExited: stateFile.reload()
    }

    FileView {
        id: stateFile
        path: root.dir + "/dictate.state"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const t = text()
            const get = (k, d) => { const m = t.match(new RegExp("^" + k + "=(.*)$", "m")); return m ? m[1] : d }
            root.state = get("state", "idle")
            root.mode = get("mode", "text")
        }
        onLoadFailed: root.state = "idle"
    }

    Rectangle {
        id: mic
        anchors.fill: parent
        radius: Theme.radiusSm
        color: root.state === "listening" ? Theme.red
             : root.state === "working" ? Theme.alpha(Theme.accent, 0.25)
             : ma.containsMouse ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.fast } }

        // pulse while listening
        SequentialAnimation on scale {
            running: root.state === "listening"; loops: Animation.Infinite
            NumberAnimation { to: 1.12; duration: 450; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0;  duration: 450; easing.type: Easing.InOutSine }
        }
        onScaleChanged: if (root.state !== "listening" && scale !== 1) scale = 1

        Icon {
            anchors.centerIn: parent
            name: root.state === "working" ? "refresh" : root.state === "listening" ? "mic" : "voice-type"
            size: 16
            color: root.state === "listening" ? Theme.onAccent : root.state === "working" ? Theme.accent : Theme.text2
            RotationAnimation on rotation { running: root.state === "working"; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
            onRotationChanged: if (root.state !== "working" && rotation !== 0) rotation = 0
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton) {
                    Quickshell.execDetached(["bash", "-lc", "command -v praxis-dictate >/dev/null && praxis-dictate || /usr/local/bin/praxis-dictate || ~/.local/bin/praxis-dictate || ~/aios/iso/airootfs/usr/local/bin/praxis-dictate"])
                } else if (mouse.button === Qt.RightButton) {
                    help.shown = !help.shown
                }
            }
        }
    }

    // Hover tooltip
    Glass {
        id: tooltip
        visible: opacity > 0
        opacity: ma.containsMouse && !help.shown && root.state === "idle" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        anchors.top: mic.bottom; anchors.topMargin: 8; anchors.horizontalCenter: mic.horizontalCenter
        width: tipTxt.implicitWidth + 16; height: 24
        radius: Theme.radiusSm
        color: Theme.glassStrong
        Text {
            id: tipTxt
            anchors.centerIn: parent
            text: "Voice Typing (Super+H)"
            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs
        }
    }

    // ── right-click help ───────────────────────────────────────────────
    Glass {
        id: help
        property bool shown: false
        visible: opacity > 0
        opacity: shown ? 1 : 0
        anchors.top: mic.bottom; anchors.topMargin: 10; anchors.right: mic.right
        width: 310; height: hcol.implicitHeight + 28
        radius: Theme.radiusMd
        color: Theme.glassStrong
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Column {
            id: hcol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 6
            Text { text: "Voice Typing (Dictation)"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
            Text { text: "Click or press Super+H to speak. Click again (or press Super+H) to type directly into whatever window has focus."; color: Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontXs; width: hcol.width; wrapMode: Text.WordWrap }
            Rectangle { width: parent.width; height: 1; color: Theme.border }
            Text { text: "Shortcuts:"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold }
            Text { text: "• Super+H: Dictate text into active window\n• Super+Shift+H: Voice command helper\n• Say 'new line' or 'new paragraph' while speaking"; color: Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontXs; width: hcol.width; wrapMode: Text.WordWrap }
        }
        MouseArea { anchors.fill: parent; onClicked: help.shown = false }
    }
}
