import QtQuick
import "root:/Config"

// Round-rect button with hover, press and active states.
Rectangle {
    id: root
    property string icon: "sparkle"
    property real   iconSize: 16
    property bool   active: false
    property color  activeColor: Theme.accent
    property color  iconColor: active ? Theme.onAccent : Theme.text2
    property string label: ""            // optional text next to the icon
    property int    padding: 8
    property bool   badge: false
    property color  badgeColor: Theme.accent
    property real   level: 1.0           // passthrough for battery
    property bool   charging: false
    property alias  hovered: ma.containsMouse
    signal clicked(var mouse)
    signal rightClicked()

    implicitWidth:  Math.max(28, ic.width + (lbl.visible ? lbl.width + 6 : 0) + padding * 2)
    implicitHeight: 28
    radius: Theme.radiusSm
    color: active ? activeColor
         : ma.pressed ? Theme.pressed
         : ma.containsMouse ? Theme.hover
         : "transparent"
    scale: ma.pressed ? 0.94 : 1.0

    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Theme.easeMove } }

    Row {
        anchors.centerIn: parent
        spacing: 6
        Icon {
            id: ic
            name: root.icon; size: root.iconSize
            color: root.iconColor
            level: root.level; charging: root.charging
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
        Text {
            id: lbl
            visible: root.label !== ""
            text: root.label
            color: root.active ? Theme.onAccent : Theme.text
            font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Rectangle {
        visible: root.badge
        width: 7; height: 7; radius: 3.5
        color: root.badgeColor
        anchors { top: parent.top; right: parent.right; margins: 5 }
        border.width: 1.5; border.color: Theme.bg
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => { if (mouse.button === Qt.RightButton) root.rightClicked(); else root.clicked(mouse) }
    }
}
