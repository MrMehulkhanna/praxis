import QtQuick
import Quickshell
import Quickshell.Io
import "root:/Config"
import "root:/Services"
import "root:/components"

// AI drawer: chat + PC control through the same backend as the CLI and
// browser. Model selection here changes it everywhere.
OverlayWindow {
    id: win
    name: "ai"
    scrim: false
    onOpened: { Aios.refreshWanted++; Aios.refresh(); input.forceActiveFocus() }
    onOpenChanged: if (!open) { Aios.refreshWanted = Math.max(0, Aios.refreshWanted - 1); picker.shown = false }

    Glass {
        id: card
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        anchors.topMargin: Theme.barHeight + Theme.barMargin + 8
        anchors.bottomMargin: Theme.dockIcon + 16 + Theme.dockMargin + 12
        anchors.rightMargin: win.open ? Theme.barMargin : -(width + 24)
        Behavior on anchors.rightMargin { NumberAnimation { duration: Theme.slow; easing.type: Theme.easeMove } }
        width: 440
        radius: Theme.radiusXl
        color: Theme.glassStrong
        MouseArea { anchors.fill: parent; onClicked: picker.shown = false }

        // staged attachments (paths): images go to a vision model, other
        // files are read into the prompt by praxis-chat-image text
        property var attachments: []
        readonly property var stagedImages: attachments.filter(p => isImage(p))
        readonly property var stagedFiles: attachments.filter(p => !isImage(p))
        property bool reading: false
        function isImage(p) { return /\.(png|jpe?g|webp|gif|bmp)$/i.test(p) }
        function baseName(p) { return p.replace(/.*\//, "") }
        function addPaths(out) {
            const add = out.split("\n").map(l => l.trim().replace(/^file:\/\//, "")).filter(l => l && attachments.indexOf(l) === -1)
            if (add.length) attachments = attachments.concat(add)
        }

        // The panel covers the screen and holds the keyboard, so the file
        // dialog and the screen selection would open underneath it: step
        // aside while they run, come back with the result.
        property var helperCmd: []
        function runHelper(cmd) {
            if (helper.running) return
            helperCmd = cmd
            Shell.closeAll()
            helperDelay.restart()
        }
        Timer {    // let the panel slide away first, so a screenshot doesn't catch it
            id: helperDelay; interval: Theme.slow + 80
            onTriggered: { helper.command = card.helperCmd; helper.running = true }
        }
        Process {
            id: helper
            stdout: StdioCollector { onStreamFinished: card.addPaths(this.text) }
            onExited: Shell.open("ai")
        }
        // Ctrl+V: an image or files copied in a file manager become
        // attachments; anything else is pasted as text
        Process {
            id: pasteProc
            command: ["praxis-chat-image", "paste"]
            stdout: StdioCollector { id: pasteOut }
            onExited: code => { if (code === 0) card.addPaths(pasteOut.text); else input.paste() }
        }
        // documents → text for the model, then send
        property string pendingText: ""
        Process {
            id: readProc
            stdout: StdioCollector {
                onStreamFinished: {
                    Aios.send(card.pendingText, card.stagedImages, card.stagedFiles, this.text)
                    card.attachments = []
                    card.reading = false
                }
            }
        }

        DropArea {
            anchors.fill: parent
            onEntered: drag => { if (drag.hasUrls) drag.acceptProposedAction() }
            onDropped: drop => {
                if (drop.hasUrls)
                    card.addPaths(Array.from(drop.urls).map(u => decodeURIComponent(u.toString())).join("\n"))
            }
        }

        // ── header ──
        Item {
            id: header
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            height: 40
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 10
                Rectangle {
                    width: 32; height: 32; radius: 16; color: Theme.alpha(Theme.accent, 0.15)
                    anchors.verticalCenter: parent.verticalCenter
                    Icon { anchors.centerIn: parent; name: "sparkle"; size: 17; color: Theme.accent }
                    Rectangle {
                        width: 9; height: 9; radius: 4.5; color: Aios.online ? Theme.green : Theme.red
                        anchors { right: parent.right; bottom: parent.bottom }
                        border.width: 2; border.color: Theme.surface
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "Praxis"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontLg; font.weight: Font.Bold }
                    Text {
                        text: !Aios.online ? (Modes.aiOn ? "backend offline" : Modes.game ? "off for Game mode" : "AI is off") : Aios.streaming ? "thinking…" : Aios.loadedModel ? "ready · model loaded" : "ready · loads on first message"
                        color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs
                    }
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4
                // model selector
                Rectangle {
                    id: modelBtn
                    height: 30; width: mrow.width + 20; radius: 15
                    color: picker.shown ? Theme.alpha(Theme.accent, 0.2) : mbMa.containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.06)
                    border.width: 1; border.color: Theme.border
                    anchors.verticalCenter: parent.verticalCenter
                    Row {
                        id: mrow; anchors.centerIn: parent; spacing: 6
                        Icon { name: Aios.autoRouting ? "layers" : Aios.selectedInfo && Aios.selectedInfo.paid ? "cloud" : "chip"; size: 13; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: Aios.selectedLabel || "model"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                        Icon { name: "chevron-down"; size: 12; color: Theme.muted; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: mbMa; anchors.fill: parent; hoverEnabled: true; onClicked: picker.shown = !picker.shown }
                }
                // Forget stored conversations — destructive, so it needs a second
                // click within 3 s (the button turns red and says so).
                IconButton {
                    id: forgetBtn
                    property bool armed: false
                    icon: "trash"; iconSize: 14
                    iconColor: armed ? Theme.red : Theme.text2
                    label: armed ? "Forget all chats?" : ""
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        if (!armed) { armed = true; disarm.restart(); return }
                        armed = false
                        Aios.forgetConversations()
                    }
                    Timer { id: disarm; interval: 3000; onTriggered: forgetBtn.armed = false }
                }
                // Open the full Praxis web UI served by the AIOS backend
                IconButton { icon: "monitor"; iconSize: 14; anchors.verticalCenter: parent.verticalCenter; onClicked: { Quickshell.execDetached(["xdg-open", Aios.base + "/"]); Shell.closeAll(); } }
                IconButton { icon: "plus"; iconSize: 14; anchors.verticalCenter: parent.verticalCenter; onClicked: { Aios.clearChat(); picker.shown = false } }
                IconButton { icon: "x"; iconSize: 14; onClicked: Shell.closeAll(); anchors.verticalCenter: parent.verticalCenter }
            }
        }

        // ── status chips ──
        Flow {
            id: chips
            anchors { top: header.bottom; left: parent.left; right: parent.right; margins: 14; topMargin: 8 }
            spacing: 6
            component Chip: Rectangle {
                property string icon: ""
                property string text: ""
                property bool on: false
                property bool clickable: false
                signal clicked()
                height: 24; width: cr.width + 16; radius: 12
                color: on ? Theme.alpha(Theme.accent, 0.2) : cma.containsMouse && clickable ? Theme.hover : Theme.alpha(Theme.text, 0.05)
                border.width: 1; border.color: on ? Theme.alpha(Theme.accent, 0.5) : Theme.border
                Row {
                    id: cr; anchors.centerIn: parent; spacing: 5
                    Icon { visible: parent.parent.icon !== ""; name: parent.parent.icon; size: 11; color: parent.parent.on ? Theme.accent : Theme.muted; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: parent.parent.text; color: parent.parent.on ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontXs; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; enabled: parent.clickable; onClicked: parent.clicked() }
            }
            Chip { visible: !!Aios.lastRoute.model; icon: (Aios.lastRoute.mode === "CLOUD") ? "cloud" : "chip"; text: (Aios.lastRoute.mode || "LOCAL") + " · " + ((Aios.models.find(m => m.id === Aios.lastRoute.model) || {}).label || Aios.lastRoute.model || "") + (Aios.lastRoute.task ? " · " + Aios.lastRoute.task : ""); on: true }
            Chip { visible: !Modes.aiOn; icon: "power"; text: Modes.game ? "Game mode is on · end it" : "AI is off · turn on"; on: true; clickable: true; onClicked: Modes.game ? Modes.toggleGame() : Modes.toggleAi() }
            Chip { icon: "layers"; text: Aios.memoryObjects + " memories" }
            Chip { visible: !Aios.netOnline; icon: "wifi-off"; text: "offline · local only" }
            Chip { icon: Aios.budgetMode === "UNRESTRICTED" ? "cloud" : "lock"; text: Aios.budgetMode === "ZERO_COST" ? "₹0 · local only" : Aios.budgetMode; on: Aios.budgetMode !== "ZERO_COST" }
            Chip { visible: !!Aios.lastMeta.context_tokens; icon: "info"; text: (Aios.lastMeta.context_tokens || 0) + " ctx tok · " + (Aios.lastMeta.retrieved || 0) + " recalled" }
            Chip { icon: "brain"; text: "Deep thinking"; on: Aios.thinking; clickable: true; onClicked: Aios.setThinking(!Aios.thinking) }
            Chip { visible: Aios.loadedModel !== ""; icon: "gpu"; text: "free VRAM"; clickable: true; onClicked: Aios.unload() }
        }

        // ── messages ──
        ListView {
            id: list
            anchors { top: chips.bottom; left: parent.left; right: parent.right; bottom: stagedTray.visible ? stagedTray.top : (pendingCard.visible ? pendingCard.top : inputBar.top); margins: 14; topMargin: 10; bottomMargin: 10 }
            model: Aios.messages
            spacing: 8
            clip: true
            onCountChanged: positionViewAtEnd()
            Connections { target: Aios; function onStreamingChanged() { list.positionViewAtEnd() } }
            header: Item {
                width: list.width; height: Aios.messages.count ? 0 : 140
                visible: Aios.messages.count === 0
                Column {
                    anchors.centerIn: parent; spacing: 6
                    Icon { name: "sparkle"; size: 28; color: Theme.alpha(Theme.accent, 0.5); anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: "Ask anything, or control the PC"; color: Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontMd; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: "Start with  !  to run a command  —  e.g.  ! open firefox"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: "Attach files or a screenshot, or paste and drop them in"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: "Nothing leaves this machine in ₹0 mode."; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
            delegate: Item {
                id: msg
                required property var model
                required property int index
                width: list.width
                height: bubble.height + (metaTxt.visible ? metaTxt.height + 3 : 0)
                readonly property bool isUser: model.role === "user"
                readonly property bool isSys: model.role === "sys"
                readonly property var imgs: (model.images || "").split("\n").filter(p => p)
                readonly property var docs: (model.files || "").split("\n").filter(p => p)
                HoverHandler { id: msgHover }
                Rectangle {
                    id: bubble
                    anchors.right: isUser ? parent.right : undefined
                    anchors.left: isUser ? undefined : parent.left
                    width: Math.min(list.width * 0.88, Math.max(body.implicitWidth, attFlow.implicitWidth) + 24)
                    height: bCol.implicitHeight + 18
                    radius: Theme.radiusLg
                    color: isUser ? Theme.alpha(Theme.accent, 0.22) : isSys ? Theme.alpha(Theme.green, 0.08) : Theme.alpha(Theme.text, 0.06)
                    border.width: 1; border.color: isUser ? Theme.alpha(Theme.accent, 0.35) : Theme.border
                    Column {
                        id: bCol
                        anchors { left: parent.left; top: parent.top; margins: 12; topMargin: 9 }
                        spacing: 6
                        Flow {
                            id: attFlow
                            visible: msg.imgs.length + msg.docs.length > 0
                            width: Math.min(list.width * 0.88 - 24, 320)
                            spacing: 6
                            Repeater {
                                model: msg.imgs
                                Rectangle {
                                    required property var modelData
                                    width: Math.min(attFlow.width, 220)
                                    height: 130
                                    radius: Theme.radiusSm
                                    color: Theme.surface2
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: "file://" + parent.modelData
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["xdg-open", parent.modelData])
                                    }
                                }
                            }
                            Repeater {
                                model: msg.docs
                                Rectangle {
                                    required property var modelData
                                    width: Math.min(docRow.implicitWidth + 18, attFlow.width); height: 28
                                    radius: Theme.radiusSm
                                    color: docMa.containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.06)
                                    border.width: 1; border.color: Theme.border
                                    Row {
                                        id: docRow
                                        anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                                        spacing: 5
                                        Icon { name: "paperclip"; size: 12; color: Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                                        Text {
                                            text: card.baseName(parent.parent.modelData); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs
                                            elide: Text.ElideMiddle; width: Math.min(implicitWidth, attFlow.width - 40)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    MouseArea {
                                        id: docMa; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["xdg-open", parent.modelData])
                                    }
                                }
                            }
                        }
                        MessageBody {
                            id: body
                            visible: model.text.length > 0 || !attFlow.visible
                            text: model.text.length ? model.text : "…"
                            maxWidth: list.width * 0.88 - 24
                            mono: isSys
                            opacity: model.text.length ? 1 : 0.5
                        }
                    }
                }
                // copy the whole message — beside the bubble, on hover
                IconButton {
                    id: copyMsg
                    property bool done: false
                    visible: model.text.length > 0 && (msgHover.hovered || done)
                    anchors { top: bubble.top; topMargin: 2 }
                    anchors.left: isUser ? undefined : bubble.right
                    anchors.right: isUser ? bubble.left : undefined
                    anchors.leftMargin: 4; anchors.rightMargin: 4
                    icon: done ? "check" : "copy"; iconSize: 13; implicitWidth: 26; implicitHeight: 26; radius: 13
                    iconColor: done ? Theme.green : Theme.text2
                    onClicked: {
                        Quickshell.execDetached(["wl-copy", "--", model.text])
                        done = true; copyMsgReset.restart()
                    }
                    Timer { id: copyMsgReset; interval: 1400; onTriggered: copyMsg.done = false }
                }
                Text {
                    id: metaTxt
                    visible: model.meta && model.meta.length > 0
                    anchors { top: bubble.bottom; topMargin: 3 }
                    anchors.right: isUser ? parent.right : undefined
                    anchors.left: isUser ? undefined : parent.left
                    text: model.meta || ""
                    color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: 10
                    elide: Text.ElideMiddle; width: Math.min(implicitWidth, list.width * 0.86)
                }
            }
        }

        // ── pending confirmation ──
        Rectangle {
            id: pendingCard
            visible: !!Aios.pending
            anchors { left: parent.left; right: parent.right; bottom: stagedTray.visible ? stagedTray.top : inputBar.top; margins: 14; bottomMargin: 10 }
            height: pcol.implicitHeight + 24
            radius: Theme.radiusLg
            color: Theme.alpha(Theme.yellow, 0.10); border.width: 1; border.color: Theme.alpha(Theme.yellow, 0.45)
            Column {
                id: pcol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 8
                Row {
                    spacing: 8
                    Icon { name: "lock"; size: 14; color: Theme.yellow; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: Aios.pending && Aios.pending.reason && Aios.pending.reason.indexOf("fix") >= 0 ? "Proposed fix — needs your confirmation" : "Needs your confirmation"; color: Theme.yellow; font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                }
                Rectangle {
                    width: parent.width; height: cmdTxt.implicitHeight + 16; radius: Theme.radiusSm
                    color: Theme.alpha(Theme.bg, 0.6); border.width: 1; border.color: Theme.border
                    Text {
                        id: cmdTxt
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                        text: Aios.pending ? "$ " + Aios.pending.cmd : ""; color: Theme.text; font.family: Theme.fontMono; font.pixelSize: Theme.fontSm; wrapMode: Text.WrapAnywhere
                    }
                }
                Text { text: Aios.pending ? Aios.pending.reason : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontXs; width: parent.width; wrapMode: Text.WordWrap }
                Row {
                    spacing: 8
                    IconButton { icon: "check"; label: "Run"; active: true; activeColor: Theme.green; iconColor: Theme.bg; implicitHeight: 32; onClicked: Aios.confirmPending() }
                    IconButton { icon: "x"; label: "Cancel"; implicitHeight: 32; onClicked: Aios.cancelPending() }
                }
            }
        }

        // ── staged attachments ──
        Flow {
            id: stagedTray
            visible: card.attachments.length > 0
            anchors { left: parent.left; right: parent.right; bottom: inputBar.top; margins: 14; bottomMargin: 6 }
            spacing: 8
            Repeater {
                model: card.attachments
                Rectangle {
                    id: att
                    required property var modelData
                    required property int index
                    readonly property bool img: card.isImage(modelData)
                    width: img ? 52 : Math.min(fileRow.implicitWidth + 34, stagedTray.width)
                    height: img ? 52 : 30
                    radius: Theme.radiusSm
                    color: Theme.surface2; border.width: 1; border.color: Theme.alpha(Theme.accent, 0.6)
                    clip: true
                    Image {
                        visible: att.img
                        anchors.fill: parent
                        source: att.img ? "file://" + att.modelData : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Row {
                        id: fileRow
                        visible: !att.img
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 5
                        Icon { name: "paperclip"; size: 12; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: card.baseName(att.modelData); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs
                            elide: Text.ElideMiddle; width: Math.min(implicitWidth, stagedTray.width - 60)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Rectangle {
                        anchors { top: att.img ? parent.top : undefined; verticalCenter: att.img ? undefined : parent.verticalCenter; right: parent.right; margins: att.img ? 2 : 6 }
                        width: 16; height: 16; radius: 8
                        color: Qt.rgba(0, 0, 0, 0.75)
                        Text { anchors.centerIn: parent; text: "×"; color: "#fff"; font.pixelSize: 12; font.weight: Font.Bold }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const arr = [...card.attachments]
                                arr.splice(att.index, 1)
                                card.attachments = arr
                            }
                        }
                    }
                }
            }
        }

        // ── input ── (grows with the text; Enter sends, Shift+Enter breaks the line)
        Rectangle {
            id: inputBar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            height: Math.min(Math.max(46, input.contentHeight + 26), 150)
            Behavior on height { NumberAnimation { duration: Theme.fast; easing.type: Theme.easeMove } }
            radius: 23
            color: Theme.alpha(Theme.text, 0.06)
            border.width: 1; border.color: input.activeFocus ? Theme.alpha(Theme.accent, 0.6) : Theme.border
            Behavior on border.color { ColorAnimation { duration: Theme.fast } }
            readonly property bool controlMode: input.text.trim().startsWith("!")
            readonly property bool canSend: input.text.trim().length > 0 || card.attachments.length > 0
            Icon {
                id: inIcon
                anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 15 }
                name: inputBar.controlMode ? "terminal" : "sparkle"; size: 15; color: inputBar.controlMode ? Theme.yellow : Theme.accent
            }
            IconButton {
                id: attachBtn
                anchors { left: inIcon.right; leftMargin: 4; bottom: parent.bottom; bottomMargin: 10 }
                icon: "paperclip"; iconSize: 14; implicitWidth: 26; implicitHeight: 26; radius: 13
                onClicked: card.runHelper(["praxis-chat-image", "pick"])
            }
            IconButton {
                id: shotBtn
                anchors { left: attachBtn.right; leftMargin: 2; bottom: parent.bottom; bottomMargin: 10 }
                icon: "camera"; iconSize: 14; implicitWidth: 26; implicitHeight: 26; radius: 13
                onClicked: card.runHelper(["praxis-chat-image", "shot"])
            }
            Flickable {
                id: inputFlick
                anchors { left: shotBtn.right; leftMargin: 8; right: sendBtn.left; rightMargin: 8; top: parent.top; bottom: parent.bottom; topMargin: 13; bottomMargin: 13 }
                contentHeight: input.contentHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                function follow(r) {    // keep the cursor in view
                    if (contentY >= r.y) contentY = r.y
                    else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
                }
                TextEdit {
                    id: input
                    width: inputFlick.width
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontMd
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    selectionColor: Theme.alpha(Theme.accent, 0.4)
                    textFormat: TextEdit.PlainText
                    onCursorRectangleChanged: inputFlick.follow(cursorRectangle)
                    Text {
                        visible: !input.text
                        text: card.reading ? "Reading attachments…" : card.attachments.length ? "Ask about the attachment…" : "Message  ·  ! to control PC"
                        color: Theme.muted; font: input.font
                    }
                    function submit() {
                        const t = text.trim()
                        if ((!t && !card.attachments.length) || card.reading || Aios.streaming) return
                        if (t.startsWith("!")) {
                            Aios.control(t.slice(1))
                        } else if (card.stagedFiles.length) {
                            card.pendingText = t
                            card.reading = true
                            readProc.command = ["praxis-chat-image", "text"].concat(card.stagedFiles)
                            readProc.running = true
                        } else {
                            Aios.send(t, card.stagedImages)
                            card.attachments = []
                        }
                        text = ""
                    }
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                            submit(); event.accepted = true
                        } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                            pasteProc.running = true; event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            Shell.closeAll(); event.accepted = true
                        }
                    }
                }
            }
            IconButton {
                id: sendBtn
                anchors { right: parent.right; rightMargin: 6; bottom: parent.bottom; bottomMargin: 6 }
                // while an answer streams this is a stop button (frees the GPU right away)
                icon: Aios.streaming ? "stop" : "send"; iconSize: 15; implicitWidth: 34; implicitHeight: 34; radius: 17
                active: Aios.streaming || inputBar.canSend
                onClicked: Aios.streaming ? Aios.stopAnswer() : input.submit()
            }
        }


        // ── model picker popover ──
        Glass {
            id: picker
            property bool shown: false
            visible: opacity > 0
            opacity: shown ? 1 : 0
            scale: shown ? 1 : 0.96
            transformOrigin: Item.TopRight
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Theme.easePop } }
            anchors { top: header.bottom; right: parent.right; rightMargin: 14 }
            width: 380; height: pl.implicitHeight + 24
            radius: Theme.radiusLg; color: Theme.surface
            borderColor: Theme.borderStrong
            MouseArea { anchors.fill: parent }
            Column {
                id: pl
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
                spacing: 4
                Text { text: "Which brain answers"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold; bottomPadding: 4 }
                Rectangle {
                    readonly property bool sel: Aios.autoRouting
                    width: pl.width; height: 54; radius: Theme.radiusMd
                    color: sel ? Theme.alpha(Theme.accent, 0.18) : autoMa.containsMouse ? Theme.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Icon { name: "layers"; size: 16; color: parent.parent.sel ? Theme.accent : Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Text { text: "Auto"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
                            Text { text: "code → Coder · system/reasoning → 8B · chat → 4B · images → VL · keeps the loaded model when close enough"; color: Theme.muted; font.family: Theme.font; font.pixelSize: 10; width: pl.width - 60; elide: Text.ElideRight }
                        }
                    }
                    Text { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: parent.sel ? "✓" : ""; color: Theme.accent; font.pixelSize: Theme.fontXs }
                    MouseArea { id: autoMa; anchors.fill: parent; hoverEnabled: true; onClicked: { Aios.selectModel("auto"); picker.shown = false } }
                }
                Repeater {
                    model: Aios.models.filter(m => m.provider === "local" || m.available)
                    Rectangle {
                        required property var modelData
                        readonly property bool sel: modelData.id === Aios.selectedModel
                        width: pl.width; height: 54; radius: Theme.radiusMd
                        color: sel ? Theme.alpha(Theme.accent, 0.18) : rma.containsMouse && modelData.available ? Theme.hover : "transparent"
                        opacity: modelData.available ? 1 : 0.5
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                        Row {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            Icon { name: modelData.paid ? "cloud" : "chip"; size: 16; color: sel ? Theme.accent : Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Row {
                                    spacing: 6
                                    Text { text: modelData.label; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold }
                                    Text { text: modelData.role; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; anchors.baseline: parent.children[0].baseline }
                                }
                                Row {
                                    spacing: 8
                                    Text { text: "★".repeat(modelData.quality) + "☆".repeat(5 - modelData.quality); color: Theme.yellow; font.pixelSize: 10 }
                                    Text {
                                        text: modelData.speed + (modelData.measured && modelData.measured.tok_per_s ? " · " + modelData.measured.tok_per_s + " tok/s here" : "")
                                              + " · " + modelData.vram + (modelData.paid ? " · paid" : "")
                                        color: Theme.muted; font.family: Theme.font; font.pixelSize: 10
                                    }
                                }
                            }
                        }
                        Text {
                            visible: modelData.available || modelData.provider !== "local"
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: !modelData.available ? (modelData.state || "") : sel ? "✓" : ""
                            color: sel ? Theme.accent : Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs
                        }
                        Rectangle {
                            visible: !modelData.available && modelData.provider === "local"
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            width: dlRow.width + 16; height: 26; radius: 13
                            color: dlMa.containsMouse ? Theme.accent : Theme.alpha(Theme.accent, 0.15)
                            border.width: 1; border.color: Theme.accent
                            Row {
                                id: dlRow; anchors.centerIn: parent; spacing: 4
                                Icon { name: "download"; size: 12; color: dlMa.containsMouse ? Theme.onAccent : Theme.accent }
                                Text { text: "Download"; color: dlMa.containsMouse ? Theme.onAccent : Theme.accent; font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold }
                            }
                            MouseArea {
                                id: dlMa; anchors.fill: parent; hoverEnabled: true
                                onClicked: Aios.downloadModel(modelData.id)
                            }
                        }
                        MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; enabled: modelData.available; onClicked: { Aios.selectModel(modelData.id); picker.shown = false } }
                    }
                }
                Rectangle { width: pl.width; height: 1; color: Theme.border }
                Text { text: "Download from Hugging Face (GGUF):"; color: Theme.muted; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold }
                Row {
                    width: pl.width; spacing: 6
                    Rectangle {
                        width: parent.width - 86; height: 28; radius: Theme.radiusSm
                        color: Theme.surface3; border.width: 1; border.color: Theme.border
                        TextInput {
                            id: customDlInput
                            anchors { fill: parent; margins: 5 }
                            clip: true
                            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontXs
                            Text { visible: !customDlInput.text; text: "e.g. Qwen/Qwen2.5-7B-Instruct-GGUF"; color: Theme.muted; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Rectangle {
                        width: 80; height: 28; radius: Theme.radiusSm
                        color: customDlMa.containsMouse ? Theme.accent : Theme.alpha(Theme.accent, 0.2)
                        border.width: 1; border.color: Theme.accent
                        Text { anchors.centerIn: parent; text: "Download"; color: customDlMa.containsMouse ? Theme.onAccent : Theme.accent; font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold }
                        MouseArea {
                            id: customDlMa; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                if (customDlInput.text.trim()) {
                                    Aios.downloadModel(customDlInput.text.trim())
                                    customDlInput.text = ""
                                    picker.shown = false
                                }
                            }
                        }
                    }
                }
                Row {
                    width: pl.width; spacing: 8
                    Rectangle {
                        height: 24; width: keyRow.width + 14; radius: 12
                        color: keyMa.containsMouse ? Theme.hover : Theme.alpha(Theme.text, 0.05)
                        border.width: 1; border.color: Theme.border
                        Row { id: keyRow; anchors.centerIn: parent; spacing: 4
                            Icon { name: "gear"; size: 11; color: Theme.muted }
                            Text { text: "Configure Cloud API Keys"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 10 }
                        }
                        MouseArea { id: keyMa; anchors.fill: parent; hoverEnabled: true; onClicked: { Shell.settings("AI"); picker.shown = false } }
                    }
                }
                Text { text: "Cloud providers (" + Aios.providers.length + " configured in providers.json) appear once an API key is set and budget mode allows them."; color: Theme.muted; font.family: Theme.font; font.pixelSize: 10; width: pl.width; wrapMode: Text.WordWrap; topPadding: 4 }
            }
        }
    }
}
