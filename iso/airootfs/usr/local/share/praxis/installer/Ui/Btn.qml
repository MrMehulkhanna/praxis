import QtQuick
import "root:/State"

// Text button: primary (accent), danger (red) or quiet.
Rectangle {
    id: b
    property string text: ""
    property bool primary: false
    property bool danger: false
    property bool enabled: true
    signal clicked()
    implicitWidth: lbl.implicitWidth + 36
    implicitHeight: 40
    radius: 12
    color: !enabled ? T.surface3 : danger ? T.red : primary ? T.accent : ma.containsMouse ? T.surface3 : T.surface2
    border.width: primary || danger ? 0 : 1
    border.color: T.borderStrong
    opacity: enabled ? 1 : 0.5
    scale: ma.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: T.fast } }
    Behavior on scale { NumberAnimation { duration: T.fast } }
    Text {
        id: lbl
        anchors.centerIn: parent
        text: b.text
        color: (b.primary || b.danger) && b.enabled ? T.accentInk : T.text
        font.family: T.font; font.pixelSize: 14; font.weight: Font.DemiBold
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: b.enabled; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
}
