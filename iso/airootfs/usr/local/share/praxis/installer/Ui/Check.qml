import QtQuick
import "root:/State"

// Switch with a label and a one-line explanation.
Item {
    id: c
    property bool checked: false
    property string text: ""
    property string sub: ""
    signal toggled(bool value)
    implicitHeight: Math.max(40, col.implicitHeight)
    implicitWidth: 420
    Column {
        id: col
        anchors { left: parent.left; right: sw.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 2
        Text { text: c.text; color: T.text; font.family: T.font; font.pixelSize: 14; font.weight: Font.DemiBold; width: parent.width; wrapMode: Text.WordWrap }
        Text { visible: c.sub !== ""; text: c.sub; color: T.muted; font.family: T.font; font.pixelSize: 12; width: parent.width; wrapMode: Text.WordWrap }
    }
    Rectangle {
        id: sw
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 44; height: 24; radius: 12
        color: c.checked ? T.accent : T.surface3
        border.width: 1; border.color: c.checked ? "transparent" : T.borderStrong
        Behavior on color { ColorAnimation { duration: T.normal } }
        Rectangle {
            width: 18; height: 18; radius: 9; y: 3
            x: c.checked ? parent.width - width - 3 : 3
            color: c.checked ? T.accentInk : T.text
            Behavior on x { NumberAnimation { duration: T.normal; easing.type: Easing.OutCubic } }
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: c.toggled(!c.checked) }
}
