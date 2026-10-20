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

    // split into [{code:bool, isImage:bool, lang, body, alt, src}]
    function segments(t) {
        const out = []
        const re = /```([a-zA-Z0-9_+-]*)\n?([\s\S]*?)```/g
        let last = 0, m
        function addProse(chunk) {
            if (!chunk) return
            const imgRe = /!\[(.*?)\]\((.*?)\)/g
            let pLast = 0, pm
            while ((pm = imgRe.exec(chunk)) !== null) {
                if (pm.index > pLast) {
                    const txt = chunk.slice(pLast, pm.index)
                    if (txt) out.push({ code: false, isImage: false, body: txt })
                }
                out.push({ code: false, isImage: true, alt: pm[1], src: pm[2] })
                pLast = imgRe.lastIndex
            }
            if (pLast < chunk.length) {
                const txt = chunk.slice(pLast)
                if (txt) out.push({ code: false, isImage: false, body: txt })
            }
        }
        while ((m = re.exec(t)) !== null) {
            if (m.index > last) addProse(t.slice(last, m.index))
            out.push({ code: true, isImage: false, lang: m[1] || "", body: m[2].replace(/\n$/, "") })
            last = re.lastIndex
        }
        if (last < t.length) addProse(t.slice(last))
        if (!out.length) out.push({ code: false, isImage: false, body: t })
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
        model: root.mono ? [{ code: false, isImage: false, body: root.text, plainmono: true }] : root.segments(root.text)
        delegate: Loader {
            required property var modelData
            sourceComponent: modelData.code ? codeBlock : (modelData.isImage ? imageBlock : prose)
            onLoaded: { item.seg = modelData }
        }
    }

    Component {
        id: imageBlock
        Rectangle {
            property var seg
            width: root.maxWidth
            height: Math.min(imgItem.implicitHeight, 200)
            radius: Theme.radiusMd
            color: Theme.surface2
            clip: true
            Image {
                id: imgItem
                anchors.fill: parent
                source: seg && seg.src ? (seg.src.startsWith("http://") || seg.src.startsWith("https://") || seg.src.startsWith("data:") ? seg.src : ("file://" + seg.src.replace(/^file:\/\//, ""))) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (seg && seg.src && !seg.src.startsWith("data:")) {
                        Quickshell.execDetached(["xdg-open", seg.src.replace(/^file:\/\//, "")])
                    }
                }
            }
        }
    }

    // TextEdit (read-only) rather than Text, so any part of an answer can be
    // selected with the mouse and copied with Ctrl+C
    Component {
        id: prose
        TextEdit {
            property var seg
            width: root.maxWidth
            readOnly: true
            selectByMouse: true
            selectionColor: Theme.alpha(Theme.accent, 0.4)
            selectedTextColor: Theme.text
            text: seg.plainmono ? seg.body : root.mdInline((seg.body || "").replace(/^\n+|\n+$/g, "")).replace(/\n/g, "<br>")
            visible: text.length > 0
            color: Theme.text
            font.family: seg.plainmono ? Theme.fontMono : Theme.font
            font.pixelSize: seg.plainmono ? Theme.fontXs : Theme.fontMd
            textFormat: seg.plainmono ? TextEdit.PlainText : TextEdit.RichText
            wrapMode: TextEdit.Wrap
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
                                Quickshell.execDetached(["wl-copy", "--", seg.body])
                                copyBtn.done = true; copyReset.restart()
                            }
                        }
                        Timer { id: copyReset; interval: 1400; onTriggered: copyBtn.done = false }
                    }
                }
                // the code
                TextEdit {
                    anchors { left: parent.left; right: parent.right; margins: 10 }
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 8
                    readOnly: true; selectByMouse: true
                    selectionColor: Theme.alpha(Theme.accent, 0.4)
                    text: seg.body
                    color: Theme.text
                    font.family: Theme.fontMono; font.pixelSize: Theme.fontSm
                    wrapMode: TextEdit.WrapAnywhere
                    textFormat: TextEdit.PlainText
                }
            }
        }
    }
}
