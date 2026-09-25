import QtQuick
import "root:/Config"
import "root:/Services"

// Push-to-talk mic in the bar. Hold = record; release = process.
// Shows a transient toast with transcript + reply.
Item {
    id: root
    implicitWidth: 28; implicitHeight: 28

    Rectangle {
        id: mic
        anchors.fill: parent
        radius: Theme.radiusSm
        color: Voice.listening ? Theme.red
             : Voice.processing ? Theme.alpha(Theme.accent, 0.25)
             : ma.containsMouse ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.fast } }

        // pulse while listening
        SequentialAnimation on scale {
            running: Voice.listening; loops: Animation.Infinite
            NumberAnimation { to: 1.12; duration: 450; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0;  duration: 450; easing.type: Easing.InOutSine }
        }
        onScaleChanged: if (!Voice.listening && scale !== 1) scale = 1

        Icon {
            anchors.centerIn: parent
            name: Voice.processing ? "refresh" : "mic"
            size: 16
            color: Voice.listening ? Theme.onAccent : Voice.processing ? Theme.accent : Theme.text2
            RotationAnimation on rotation { running: Voice.processing; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
            onRotationChanged: if (!Voice.processing && rotation !== 0) rotation = 0
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: mouse => { if (mouse.button === Qt.LeftButton) Voice.startListening() }
            onReleased: mouse => { if (mouse.button === Qt.LeftButton) Voice.stopListening() }
            onClicked: mouse => { if (mouse.button === Qt.RightButton) help.shown = !help.shown }
        }
    }

    // ── toast ──────────────────────────────────────────────────────────
    Glass {
        id: toast
        property bool shown: false
        visible: opacity > 0
        opacity: shown ? 1 : 0
        anchors.top: mic.bottom; anchors.topMargin: 10; anchors.right: mic.right
        width: 320; height: col.implicitHeight + 24
        radius: Theme.radiusMd
        color: Theme.glassStrong
        scale: shown ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Theme.easePop } }

        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 4
            Text {
                width: parent.width; visible: text.length > 0
                text: Voice.lastTranscript
                color: Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontXs; font.italic: true
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width; visible: text.length > 0
                text: Voice.lastReply
                color: Voice.lastKind === "refused" ? Theme.red : Theme.text
                font.family: Theme.font; font.pixelSize: Theme.fontSm
                wrapMode: Text.WordWrap
            }
        }
        Connections {
            target: Voice
            function onLastReplyChanged() { if (Voice.lastReply.length) { toast.shown = true; hide.restart() } }
        }
        Timer { id: hide; interval: 7000; onTriggered: toast.shown = false }
        MouseArea { anchors.fill: parent; onClicked: toast.shown = false }
    }

    // ── right-click help ───────────────────────────────────────────────
    Glass {
        id: help
        property bool shown: false
        visible: opacity > 0
        opacity: shown ? 1 : 0
        anchors.top: mic.bottom; anchors.topMargin: 10; anchors.right: mic.right
        width: 300; height: hcol.implicitHeight + 28
        radius: Theme.radiusMd
        color: Theme.glassStrong
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Column {
            id: hcol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 5
            Text { text: "Voice — hold the mic and speak"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
            Repeater {
                model: ["volume up / down / to 50", "brightness up / down / to 60", "mute", "workspace 3",
                        "open browser / terminal / files", "lock screen · suspend (confirm)", "free vram",
                        "anything else → asks the AI"]
                Text { text: "•  " + modelData; color: Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontXs; width: hcol.width; wrapMode: Text.WordWrap }
            }
        }
        MouseArea { anchors.fill: parent; onClicked: help.shown = false }
    }
}
