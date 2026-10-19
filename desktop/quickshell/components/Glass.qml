import QtQuick
import "root:/Config"

// Frosted glass surface: soft layered shadow, translucent body, hairline
// border and a 1px light edge on top. Hyprland blurs whatever is behind.
Item {
    id: root
    property real  radius: Theme.radiusLg
    property color color: Theme.glass
    property color borderColor: Theme.border
    property bool  shadow: true
    property real  shadowStrength: 1.0
    default property alias content: inner.data

    // two soft shadow layers — cheap, no shader
    Rectangle {
        visible: root.shadow
        anchors.fill: parent; anchors.margins: -6; anchors.topMargin: 2
        radius: root.radius + 6
        color: Theme.alpha(Theme.shadow, 0.35 * root.shadowStrength)
        z: -2
    }
    Rectangle {
        visible: root.shadow
        anchors.fill: parent; anchors.margins: -2; anchors.topMargin: 1
        radius: root.radius + 2
        color: Theme.alpha(Theme.shadow, 0.5 * root.shadowStrength)
        z: -1
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: root.radius
        color: root.color
        border.width: 1
        border.color: root.borderColor

        // top edge highlight
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
            anchors.leftMargin: root.radius; anchors.rightMargin: root.radius
            height: 1
            color: Theme.highlight
        }
    }

    Item { id: inner; anchors.fill: parent }
}
