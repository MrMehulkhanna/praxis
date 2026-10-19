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

        property var stagedImages: []
        function addImage(path) {
            if (!path) return
            const p = path.trim()
            if (p && stagedImages.indexOf(p) === -1) {
                stagedImages = stagedImages.concat([p])
            }
        }

        Process {
            id: imgPickProc
            command: ["praxis-chat-image", "pick"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const p = this.text.trim()
                    if (p) card.addImage(p)
                }
            }
        }
        Process {
            id: imgShotProc
            command: ["praxis-chat-image", "shot"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const p = this.text.trim()
                    if (p) card.addImage(p)
                }
            }
        }
        Process {
            id: imgPasteProc
            command: ["praxis-chat-image", "paste"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const p = this.text.trim()
                    if (p) card.addImage(p)
                }
            }
        }

        DropArea {
            anchors.fill: parent
            onEntered: drag => {
                if (drag.hasUrls) drag.acceptProposedAction()
            }
            onDropped: drop => {
                if (drop.hasUrls) {
                    for (let i = 0; i < drop.urls.length; i++) {
                        let u = drop.urls[i].toString()
                        if (/\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(u)) {
                            card.addImage(u.replace(/^file:\/\//, ""))
                        }
                    }
                }
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
                    Text { text: "Attach images with 📷 or paste / drop screenshots directly"; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: "Nothing leaves this machine in ₹0 mode."; color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
            delegate: Item {
                required property var model
                required property int index
                width: list.width
                height: bubble.height + (metaTxt.visible ? metaTxt.height + 3 : 0)
                readonly property bool isUser: model.role === "user"
                readonly property bool isSys: model.role === "sys"
                Rectangle {
                    id: bubble
                    anchors.right: isUser ? parent.right : undefined
                    anchors.left: isUser ? undefined : parent.left
                    width: Math.min(list.width * 0.88, Math.max(body.implicitWidth, msgImgFlow.implicitWidth) + 24)
                    height: bCol.implicitHeight + 18
                    radius: Theme.radiusLg
                    color: isUser ? Theme.alpha(Theme.accent, 0.22) : isSys ? Theme.alpha(Theme.green, 0.08) : Theme.alpha(Theme.text, 0.06)
                    border.width: 1; border.color: isUser ? Theme.alpha(Theme.accent, 0.35) : Theme.border
                    Column {
                        id: bCol
                        anchors { left: parent.left; top: parent.top; margins: 12; topMargin: 9 }
                        spacing: 6
                        Flow {
                            id: msgImgFlow
                            visible: !!(model.images && (model.images.count || model.images.length))
                            width: Math.min(list.width * 0.88 - 24, 320)
                            spacing: 6
                            Repeater {
                                model: model.images
                                Rectangle {
                                    required property var modelData
                                    width: Math.min(msgImgFlow.width, 220)
                                    height: 130
                                    radius: Theme.radiusSm
                                    color: Theme.surface2
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: (typeof modelData === "string") ? (modelData.startsWith("data:") ? modelData : ("file://" + modelData.replace(/^file:\/\//, ""))) : ""
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (typeof modelData === "string" && !modelData.startsWith("data:")) {
                                                Quickshell.execDetached(["xdg-open", modelData.replace(/^file:\/\//, "")])
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        MessageBody {
                            id: body
                            text: model.text.length ? model.text : (msgImgFlow.visible ? "" : "…")
                            maxWidth: list.width * 0.88 - 24
                            mono: isSys
                            opacity: model.text.length || msgImgFlow.visible ? 1 : 0.5
                        }
                    }
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

        // ── staged images tray ──
        Flow {
            id: stagedTray
            visible: card.stagedImages.length > 0
            anchors { left: parent.left; right: parent.right; bottom: inputBar.top; margins: 14; bottomMargin: 6 }
            spacing: 8
            Repeater {
                model: card.stagedImages
                Rectangle {
                    required property var modelData
                    required property int index
                    width: 52; height: 52; radius: Theme.radiusSm
                    color: Theme.surface2; border.width: 1; border.color: Theme.accent
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: modelData.startsWith("data:") ? modelData : ("file://" + modelData.replace(/^file:\/\//, ""))
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Rectangle {
                        anchors { top: parent.top; right: parent.right; margins: 2 }
                        width: 16; height: 16; radius: 8
                        color: Qt.rgba(0, 0, 0, 0.75)
                        Text { anchors.centerIn: parent; text: "×"; color: "#fff"; font.pixelSize: 12; font.weight: Font.Bold }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const arr = [...card.stagedImages]
                                arr.splice(index, 1)
                                card.stagedImages = arr
                            }
                        }
                    }
                }
            }
        }

        // ── input ──
        Rectangle {
            id: inputBar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            height: 46; radius: 23
            color: Theme.alpha(Theme.text, 0.06)
            border.width: 1; border.color: input.activeFocus ? Theme.alpha(Theme.accent, 0.6) : Theme.border
            Behavior on border.color { ColorAnimation { duration: Theme.fast } }
            readonly property bool controlMode: input.text.trim().startsWith("!")
            Icon {
                id: inIcon
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                name: inputBar.controlMode ? "terminal" : "sparkle"; size: 15; color: inputBar.controlMode ? Theme.yellow : Theme.accent
            }
            IconButton {
                id: attachBtn
                anchors { left: inIcon.right; leftMargin: 4; verticalCenter: parent.verticalCenter }
                icon: "image"; iconSize: 13; implicitWidth: 26; implicitHeight: 26; radius: 13
                onClicked: imgPickProc.running = true
            }
            IconButton {
                id: shotBtn
                anchors { left: attachBtn.right; leftMargin: 2; verticalCenter: parent.verticalCenter }
                icon: "eye"; iconSize: 13; implicitWidth: 26; implicitHeight: 26; radius: 13
                onClicked: imgShotProc.running = true
            }
            TextInput {
                id: input
                anchors { left: shotBtn.right; leftMargin: 8; right: sendBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontMd
                clip: true
                selectionColor: Theme.alpha(Theme.accent, 0.4)
                Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: !input.text; text: card.stagedImages.length > 0 ? "Ask about attached image…" : "Message  ·  ! to control PC"; color: Theme.muted; font: input.font }
                function submit() {
                    const t = text.trim()
                    if (!t && card.stagedImages.length === 0) return
                    if (t.startsWith("!")) {
                        Aios.control(t.slice(1))
                    } else {
                        Aios.send(t, card.stagedImages)
                    }
                    text = ""
                    card.stagedImages = []
                }
                Keys.onReturnPressed: submit()
                Keys.onEnterPressed: submit()
                Keys.onEscapePressed: Shell.closeAll()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                        imgPasteProc.running = true
                    }
                }
            }
            IconButton {
                id: sendBtn
                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                // while an answer streams this is a stop button (frees the GPU right away)
                icon: Aios.streaming ? "stop" : "send"; iconSize: 15; implicitWidth: 34; implicitHeight: 34; radius: 17
                active: Aios.streaming || input.text.trim().length > 0 || card.stagedImages.length > 0
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
                            text: !modelData.available ? modelData.state : sel ? "✓" : ""
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
