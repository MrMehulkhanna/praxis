import QtQuick
import Quickshell
import "root:/Config"

// Renders assistant/user text with fenced ``` code blocks pulled out into
// monospace cards with a copy button. Prose gets light markdown (bold,
// `inline code`). Everything else stays plain and readable.
Column {
    id: root
    property string text: ""
    property real maxWidth: 360
    property bool mono: false          // sys messages: render the whole thing mono
    spacing: 8

    // split into [{code:bool, lang, body}]
    function segments(t) {
        const out = []
        const re = /```([a-zA-Z0-9_+-]*)\n?([\s\S]*?)```/g
        let last = 0, m
        while ((m = re.exec(t)) !== null) {
            if (m.index > last) out.push({ code: false, body: t.slice(last, m.index) })
            out.push({ code: true, lang: m[1] || "", body: m[2].replace(/\n$/, "") })
            last = re.lastIndex
        }
        if (last < t.length) out.push({ code: false, body: t.slice(last) })
        if (!out.length) out.push({ code: false, body: t })
        return out
    }
    function mdInline(s) {
        // minimal, safe: escape, then bold + inline code
        s = s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        s = s.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
        s = s.replace(/`([^`]+)`/g, m => "<font face='" + Theme.fontMono + "'>" + m.slice(1, -1) + "</font>")
        return s
    }

    Repeater {
        model: root.mono ? [{ code: false, body: root.text, plainmono: true }] : root.segments(root.text)
        delegate: Loader {
            required property var modelData
            sourceComponent: modelData.code ? codeBlock : prose
            onLoaded: { item.seg = modelData }
        }
    }

    Component {
        id: prose
        Text {
            property var seg
            width: root.maxWidth
            text: seg.plainmono ? seg.body : root.mdInline((seg.body || "").replace(/^\n+|\n+$/g, ""))
            visible: text.length > 0
            color: Theme.text
            font.family: seg.plainmono ? Theme.fontMono : Theme.font
            font.pixelSize: seg.plainmono ? Theme.fontXs : Theme.fontMd
            textFormat: seg.plainmono ? Text.PlainText : Text.StyledText
            wrapMode: Text.Wrap
        }
    }

    Component {
        id: codeBlock
        Rectangle {
            property var seg
            width: root.maxWidth
            implicitHeight: codeCol.implicitHeight + 8
            height: implicitHeight
            radius: Theme.radiusMd
            color: Qt.rgba(0, 0, 0, 0.32)
            border.width: 1; border.color: Theme.border
            Column {
                id: codeCol
                anchors { left: parent.left; right: parent.right; top: parent.top }
                // header: language + copy
                Rectangle {
                    width: parent.width; height: 26
                    color: Theme.alpha(Theme.text, 0.05)
                    radius: Theme.radiusMd
                    Rectangle {  // square off the bottom corners of the header strip
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 8; color: parent.color
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: seg.lang || "code"; color: Theme.muted
                        font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.DemiBold
                    }
                    Rectangle {
                        id: copyBtn
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        width: cRow.width + 12; height: 18; radius: 6
                        color: cma.containsMouse ? Theme.hover : "transparent"
                        property bool done: false
                        Row {
                            id: cRow; anchors.centerIn: parent; spacing: 3
                            Icon { name: copyBtn.done ? "check" : "layers"; size: 11; color: copyBtn.done ? Theme.green : Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: copyBtn.done ? "copied" : "copy"; color: copyBtn.done ? Theme.green : Theme.text2; font.family: Theme.font; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea {
                            id: cma; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                Quickshell.execDetached(["bash", "-lc", "wl-copy -- " + JSON.stringify(seg.body)])
                                copyBtn.done = true; copyReset.restart()
                            }
                        }
                        Timer { id: copyReset; interval: 1400; onTriggered: copyBtn.done = false }
                    }
                }
                // the code
                Text {
                    anchors { left: parent.left; right: parent.right; margins: 10 }
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 8
                    text: seg.body
                    color: Theme.text
                    font.family: Theme.fontMono; font.pixelSize: Theme.fontSm
                    wrapMode: Text.WrapAnywhere
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
