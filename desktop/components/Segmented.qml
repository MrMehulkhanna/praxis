import QtQuick
import "root:/Config"

// Segmented control. `options` = [{value, label}] ; `value` owner-controlled.
Rectangle {
    id: root
    property var options: []
    property var value
    signal selected(var v)
    height: 30; width: row.width + 6; radius: 15
    color: Theme.alpha(Theme.text, 0.06); border.width: 1; border.color: Theme.border
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2
        Repeater {
            model: root.options
            Rectangle {
                required property var modelData
                readonly property bool on: modelData.value === root.value
                height: 24; width: t.implicitWidth + 20; radius: 12
                color: on ? Theme.accent : sma.containsMouse ? Theme.hover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Text { id: t; anchors.centerIn: parent; text: modelData.label; color: parent.on ? Theme.onAccent : Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold }
                MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; onClicked: root.selected(modelData.value) }
            }
        }
    }
}
