import QtQuick
import "root:/Config"

// Label + description on the left, control on the right.
Item {
    id: root
    property string label: ""
    property string description: ""
    default property alias control: slot.data
    width: parent ? parent.width : 400
    height: Math.max(46, slot.childrenRect.height + 16)

    Column {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: parent.width - slot.width - 16
        spacing: 2
        Text { text: root.label; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontMd; font.weight: Font.Medium; elide: Text.ElideRight; width: parent.width }
        Text { visible: root.description !== ""; text: root.description; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; wrapMode: Text.WordWrap; width: parent.width }
    }
    Item {
        id: slot
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: childrenRect.width; height: childrenRect.height
    }
    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1; color: Theme.border }
}
