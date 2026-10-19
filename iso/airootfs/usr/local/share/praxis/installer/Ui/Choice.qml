import QtQuick
import "root:/State"

// A selectable card (radio style). Disabled cards say why.
Rectangle {
    id: c
    property string title: ""
    property string sub: ""
    property string why: ""              // shown instead of sub when not possible
    property bool selected: false
    property bool possible: true
    property bool danger: false
    property color tint: danger ? T.red : T.accent
    default property alias extra: slot.data
    signal picked()
    implicitWidth: 560
    implicitHeight: col.implicitHeight + 28
    radius: T.r
    color: selected ? T.alpha(tint, 0.12) : ma.containsMouse && possible ? T.hover : T.surface
    border.width: selected ? 2 : 1
    border.color: selected ? T.alpha(tint, 0.85) : T.border
    opacity: possible ? 1 : 0.55
    Behavior on color { ColorAnimation { duration: T.fast } }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: c.possible; cursorShape: Qt.PointingHandCursor; onClicked: c.picked() }
    Rectangle {
        id: dot
        x: 16; y: 18
        width: 18; height: 18; radius: 9
        color: "transparent"
        border.width: 2; border.color: c.selected ? c.tint : T.muted
        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: c.tint; visible: c.selected }
    }
    Column {
        id: col
        anchors { left: dot.right; leftMargin: 14; right: parent.right; rightMargin: 16; top: parent.top; topMargin: 14 }
        spacing: 4
        Text { text: c.title; color: T.text; font.family: T.font; font.pixelSize: 15; font.weight: Font.DemiBold; width: parent.width; wrapMode: Text.WordWrap }
        Text {
            text: c.possible ? c.sub : c.why
            visible: text !== ""
            color: c.possible ? T.text2 : T.yellow
            font.family: T.font; font.pixelSize: 12; width: parent.width; wrapMode: Text.WordWrap
        }
        Item { id: slot; width: parent.width; height: childrenRect.height; visible: c.selected && c.possible }
    }
}
