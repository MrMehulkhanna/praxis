import QtQuick
import "root:/State"

// Labelled one-line text field. `hint` shows under it (red when `bad`).
Column {
    id: f
    property string label: ""
    property alias text: input.text
    property bool password: false
    property string placeholder: ""
    property string hint: ""
    property bool bad: false
    property alias input: input
    signal accepted()
    spacing: 6
    width: 320
    Text { text: f.label; color: T.text2; font.family: T.font; font.pixelSize: 12; font.weight: Font.DemiBold }
    Rectangle {
        width: parent.width; height: 42; radius: 11
        color: T.surface2
        border.width: 1
        border.color: f.bad ? T.alpha(T.red, 0.7) : input.activeFocus ? T.alpha(T.accent, 0.8) : T.borderStrong
        Behavior on border.color { ColorAnimation { duration: T.fast } }
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            verticalAlignment: TextInput.AlignVCenter
            color: T.text; selectionColor: T.alpha(T.accent, 0.4); selectedTextColor: T.text
            font.family: T.font; font.pixelSize: 14
            echoMode: f.password ? TextInput.Password : TextInput.Normal
            clip: true
            onAccepted: f.accepted()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !input.text && !input.activeFocus
                text: f.placeholder; color: T.muted; font: input.font
            }
        }
    }
    Text {
        visible: f.hint !== ""
        text: f.hint; width: parent.width; wrapMode: Text.WordWrap
        color: f.bad ? T.red : T.muted; font.family: T.font; font.pixelSize: 11
    }
}
