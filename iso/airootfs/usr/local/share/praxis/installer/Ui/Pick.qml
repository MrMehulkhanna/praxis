import QtQuick
import "root:/State"

// Searchable picker for long lists (time zones, keyboard layouts, languages):
// type to filter, click a match.
Column {
    id: p
    property string label: ""
    property var model: []
    property string current: ""
    property int maxRows: 5
    signal chosen(string value)
    spacing: 6
    width: 320
    readonly property var matches: {
        const q = input.text.toLowerCase().replace(/ /g, "_")
        if (!input.activeFocus || q === "" ) return []
        const out = []
        for (const m of p.model) { if (m.toLowerCase().indexOf(q) >= 0) { out.push(m); if (out.length >= p.maxRows) break } }
        return out
    }
    Text { text: p.label; color: T.text2; font.family: T.font; font.pixelSize: 12; font.weight: Font.DemiBold }
    Rectangle {
        width: parent.width; height: 42; radius: 11
        color: T.surface2; border.width: 1
        border.color: input.activeFocus ? T.alpha(T.accent, 0.8) : T.borderStrong
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            verticalAlignment: TextInput.AlignVCenter
            color: T.text; font.family: T.font; font.pixelSize: 14; clip: true
            onActiveFocusChanged: if (!activeFocus) text = ""
            onAccepted: if (p.matches.length) { p.chosen(p.matches[0]); focus = false }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !input.text
                text: p.current || "type to search"
                color: p.current && !input.activeFocus ? T.text : T.muted
                font: input.font
            }
        }
    }
    Repeater {
        model: p.matches
        Rectangle {
            required property var modelData
            width: p.width; height: 34; radius: 9
            color: hm.containsMouse ? T.surface3 : T.surface2
            Text { anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } text: modelData; color: T.text; font.family: T.font; font.pixelSize: 13 }
            MouseArea { id: hm; anchors.fill: parent; hoverEnabled: true; onClicked: { p.chosen(modelData); input.focus = false } }
        }
    }
}
