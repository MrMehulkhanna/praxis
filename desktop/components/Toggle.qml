import QtQuick
import "root:/Config"

// Animated switch. `checked` is controlled by the owner; `toggled` asks to change.
Rectangle {
    id: root
    property bool checked: false
    property bool enabled: true
    signal toggled(bool value)

    width: 40; height: 22; radius: 11
    color: checked ? Theme.accent : Theme.surface3
    border.width: 1
    border.color: checked ? Theme.alpha(Theme.accent, 0.6) : Theme.borderStrong
    opacity: enabled ? 1 : 0.4
    Behavior on color { ColorAnimation { duration: Theme.normal } }

    Rectangle {
        width: 16; height: 16; radius: 8
        y: 3
        x: root.checked ? root.width - width - 3 : 3
        color: root.checked ? Theme.onAccent : Theme.text
        Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Theme.easeMove } }
    }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        enabled: root.enabled
        onClicked: root.toggled(!root.checked)
    }
}
