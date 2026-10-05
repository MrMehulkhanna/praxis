import QtQuick
import "root:/State"
import "root:/Ui"

Column {
    spacing: 18
    Text { text: "Extra apps"; color: T.text; font.family: T.font; font.pixelSize: 24; font.weight: Font.Bold }
    Text {
        width: 640; wrapMode: Text.WordWrap
        text: "Praxis comes with Firefox, a terminal, files, screenshots, voice typing and the AI assistant. Add more now if you like — or later, any time, with the package manager."
        color: T.text2; font.family: T.font; font.pixelSize: 14
    }
    Grid {
        columns: 2; columnSpacing: 12; rowSpacing: 12
        Repeater {
            model: Inst.bundles
            Rectangle {
                required property var modelData
                readonly property bool on: Inst.apps.indexOf(modelData.id) >= 0
                width: 314; height: 96; radius: T.r
                color: on ? T.alpha(T.accent, 0.12) : am.containsMouse ? T.hover : T.surface
                border.width: on ? 2 : 1; border.color: on ? T.alpha(T.accent, 0.8) : T.border
                Behavior on color { ColorAnimation { duration: T.fast } }
                Column {
                    anchors { fill: parent; margins: 14; rightMargin: 44 }
                    spacing: 4
                    Text { text: modelData.title; color: T.text; font.family: T.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Text { text: modelData.desc; color: T.text2; font.family: T.font; font.pixelSize: 12; width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
                }
                Rectangle {
                    anchors { right: parent.right; top: parent.top; margins: 14 }
                    width: 22; height: 22; radius: 7
                    color: parent.on ? T.accent : "transparent"; border.width: 2; border.color: parent.on ? T.accent : T.muted
                    Text { anchors.centerIn: parent; visible: parent.parent.on; text: "✓"; color: T.accentInk; font.pixelSize: 13; font.weight: Font.Bold }
                }
                MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Inst.toggleApp(modelData.id) }
            }
        }
    }
}
