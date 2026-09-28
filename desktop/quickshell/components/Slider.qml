import QtQuick
import "root:/Config"

// Horizontal slider with an icon. Emits `moved(value)` only for user input;
// external `value` updates are ignored while dragging so live system
// updates never fight the hand.
Item {
    id: root
    property real   value: 0.5            // 0..1, owner-controlled
    property string icon: "sun"
    property bool   dragging: ma.pressed
    property real   shown: dragging ? _drag : value
    property real   _drag: 0
    property color  fillColor: Theme.accent
    property string valueText: Math.round(shown * 100) + "%"
    signal moved(real v)
    signal iconClicked()

    implicitHeight: 34
    implicitWidth: 200

    Icon {
        id: ic
        name: root.icon; size: 16; color: Theme.text2
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.iconClicked() }
    }

    Item {
        id: track
        anchors { left: ic.right; leftMargin: 12; right: txt.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        height: 34

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6; radius: 3
            color: Theme.surface3
            border.width: 1; border.color: Theme.border
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(6, parent.width * root.shown); height: 6; radius: 3
            color: root.fillColor
            Behavior on width { enabled: !root.dragging; NumberAnimation { duration: Theme.fast } }
        }
        Rectangle {
            id: knob
            width: 16; height: 16; radius: 8
            x: Math.max(0, Math.min(parent.width - width, parent.width * root.shown - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            border.width: 1; border.color: Theme.alpha(Theme.bg, 0.6)
            scale: ma.pressed ? 1.15 : ma.containsMouse ? 1.05 : 1
            Behavior on scale { NumberAnimation { duration: Theme.fast } }
            Behavior on x { enabled: !root.dragging; NumberAnimation { duration: Theme.fast } }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            function set(mx) {
                root._drag = Math.max(0, Math.min(1, mx / width))
                root.moved(root._drag)
            }
            onPressed: mouse => set(mouse.x)
            onPositionChanged: mouse => { if (pressed) set(mouse.x) }
            onWheel: wheel => { const v = Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))); root.moved(v) }
        }
    }

    Text {
        id: txt
        text: root.valueText
        color: Theme.text2
        font.family: Theme.fontMono; font.pixelSize: Theme.fontXs
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        width: 34; horizontalAlignment: Text.AlignRight
    }
}
