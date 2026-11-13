import QtQuick
import Quickshell
import Quickshell.Hyprland
import "root:/Config"
import "root:/Services"
import "root:/components"

// Praxis Share — use another machine's screen as a display of this one.
//
// The layout is deliberately one column of a few named sections rather than a
// wall of controls: the stage shows what you have, one block decides what to
// send, one connects to someone else, and the live figures only exist while
// something is actually running. Nothing competes for the eye at rest.
OverlayWindow {
    id: win
    name: "share"
    onOpened: { Share.refresh(); Share.checkReady(); card.forceActiveFocus() }

    property string connectTarget: ""
    property bool   copiedAddr: false
    property bool   isFullscreen: false
    Timer { id: copyTimer; interval: 1800; onTriggered: win.copiedAddr = false }

    // same shape as the Settings buttons, so the two windows match
    component Btn: IconButton { implicitHeight: 30; padding: 10 }

    Glass {
        id: card
        anchors.centerIn: parent
        width: win.isFullscreen ? parent.width - 24 : 720
        height: win.isFullscreen ? parent.height - 24 : Math.min(parent.height - 80, col.implicitHeight + 56)
        radius: win.isFullscreen ? Theme.radiusLg : Theme.radiusXl
        elevation: 3
        focus: true

        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Theme.easeMove } }
        Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Theme.easeMove } }
        Behavior on radius { NumberAnimation { duration: Theme.normal } }

        Keys.onPressed: (event) => {
            if ((event.modifiers & Qt.AltModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                win.isFullscreen = !win.isFullscreen
                event.accepted = true
            }
        }
        Keys.onEscapePressed: (event) => {
            if (win.isFullscreen) {
                win.isFullscreen = false
                event.accepted = true
            }
        }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 28
            contentWidth: width
            contentHeight: col.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: col
                width: parent.width
                spacing: Theme.spaceXl

            // ── header ─────────────────────────────────────────────────
            Item {
                width: parent.width; height: 34
                Column {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: "Share screen"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold
                    }
                    Text {
                        text: Share.serving
                            ? (Share.clients > 0 ? Share.clients + " connected" : "waiting for a connection")
                            : Share.displayCount + (Share.displayCount === 1 ? " display" : " displays")
                        color: Share.serving && Share.clients > 0 ? Theme.green : Theme.muted
                        font.family: Theme.font; font.pixelSize: Theme.fontSm
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spaceSm

                    // live dot, only when it means something
                    Rectangle {
                        visible: Share.serving
                        width: live.width + 26; height: 26; radius: 13
                        color: Theme.alpha(Theme.green, 0.14)
                        border.width: 1; border.color: Theme.alpha(Theme.green, 0.35)
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: live
                            anchors.centerIn: parent; spacing: 7
                            Rectangle {
                                width: 7; height: 7; radius: 4; color: Theme.green
                                anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on opacity {
                                    running: Share.serving; loops: Animation.Infinite
                                    NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutQuad }
                                    NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutQuad }
                                }
                            }
                            Text {
                                text: "live  ·  :" + Share.port
                                color: Theme.green
                                font.family: Theme.fontMono; font.pixelSize: Theme.fontXs
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // Fullscreen toggle button
                    IconButton {
                        icon: win.isFullscreen ? "restore" : "maximize"
                        iconSize: 14
                        iconColor: hovered ? Theme.text : Theme.muted
                        implicitHeight: 28; implicitWidth: 28; padding: 6
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: win.isFullscreen = !win.isFullscreen
                    }

                    // Close button
                    IconButton {
                        icon: "x"
                        iconSize: 14
                        iconColor: hovered ? Theme.text : Theme.muted
                        implicitHeight: 28; implicitWidth: 28; padding: 6
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: Shell.closeAll()
                    }
                }
            }

            // ── the stage: your displays, in perspective ───────────────
            // Tilted away from the viewer so the row reads as physical
            // screens standing on a desk rather than rectangles in a list.
            // The one being sent lifts and lights up, which is the whole
            // state of the feature in a single glance.
            Rectangle {
                width: parent.width; height: win.isFullscreen ? 240 : 190
                radius: Theme.radiusLg
                color: Theme.alpha(Theme.surface, 0.5)
                border.width: 1; border.color: Theme.border
                clip: true
                Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Theme.easeMove } }

                Row {
                    anchors.centerIn: parent
                    spacing: 26
                    Repeater {
                        model: Share.displays
                        delegate: Item {
                            id: screenTile
                            required property var modelData
                            required property int index
                            readonly property bool virtualDisplay: modelData.name.startsWith("HEADLESS")
                            readonly property bool sending: Share.serving && Share.servingMon === modelData.name
                            width: 150; height: 130

                            transform: [
                                Rotation {
                                    origin.x: 75; origin.y: 60
                                    axis { x: 0.22; y: 1; z: 0 }
                                    angle: screenTile.index === 0 ? 16 : (screenTile.index === 1 ? 0 : -16)
                                    Behavior on angle { NumberAnimation { duration: Theme.slow; easing.type: Theme.easeMove } }
                                },
                                Translate { y: screenTile.sending ? -8 : 0
                                    Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } } }
                            ]

                            // panel
                            Rectangle {
                                id: panel
                                width: 150; height: 92
                                radius: 7
                                color: screenTile.sending ? Theme.alpha(Theme.accent, 0.18) : Theme.alpha(Theme.bg, 0.85)
                                border.width: screenTile.sending ? 2 : 1
                                border.color: screenTile.sending ? Theme.accent
                                            : (screenTile.virtualDisplay ? Theme.alpha(Theme.purple, 0.5) : Theme.borderStrong)
                                Behavior on color { ColorAnimation { duration: Theme.normal } }

                                Icon {
                                    anchors.centerIn: parent
                                    name: screenTile.virtualDisplay ? "cloud" : "monitor"
                                    size: 26
                                    color: screenTile.sending ? Theme.accent
                                         : (screenTile.virtualDisplay ? Theme.purple : Theme.muted)
                                }
                                // a sweep across the panel while it is being sent
                                Rectangle {
                                    visible: screenTile.sending
                                    width: 46; height: parent.height - 4
                                    y: 2; radius: 6
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 0.5; color: Theme.alpha(Theme.accent, 0.16) }
                                        GradientStop { position: 1.0; color: "transparent" }
                                    }
                                    NumberAnimation on x {
                                        running: screenTile.sending; loops: Animation.Infinite
                                        from: -46; to: 150; duration: 2200; easing.type: Easing.InOutQuad
                                    }
                                }
                            }
                            // stand
                            Rectangle {
                                anchors.top: panel.bottom; anchors.horizontalCenter: panel.horizontalCenter
                                width: 16; height: 10
                                color: Theme.alpha(Theme.borderStrong, 0.8)
                            }
                            Rectangle {
                                anchors.top: panel.bottom; anchors.topMargin: 10
                                anchors.horizontalCenter: panel.horizontalCenter
                                width: 62; height: 4; radius: 2
                                color: Theme.alpha(Theme.borderStrong, 0.8)
                            }
                            Text {
                                anchors.top: panel.bottom; anchors.topMargin: 18
                                anchors.horizontalCenter: panel.horizontalCenter
                                text: screenTile.modelData.name
                                color: screenTile.sending ? Theme.accent : Theme.text2
                                font.family: Theme.fontMono; font.pixelSize: Theme.fontXs
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: Share.displayCount === 0
                    text: "no displays"
                    color: Theme.muted
                    font.family: Theme.font; font.pixelSize: Theme.fontSm
                }
            }

            // ── send ───────────────────────────────────────────────────
            Column {
                width: parent.width; spacing: Theme.spaceMd
                Text {
                    text: "SEND  ·  this screen goes to the other machine"
                    color: Theme.muted
                    font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: !Share.serving
                    text: Share.localIp
                        ? "Start here, then type this PC's address (" + Share.localIp + ":" + Share.port + ") and code into the other machine's Receive box."
                        : "Start here, then read the address and code off this window and type them into the other machine's Receive box."
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: Theme.fontSm
                }
                SettingRow {
                    label: "Mode"
                    description: Share.mode === "extend"
                        ? "Adds a display. The other machine becomes a screen of this one."
                        : "Copies a display you already have."
                    Segmented {
                        options: [{ value: "extend", label: "Extend" }, { value: "mirror", label: "Mirror" }]
                        value: Share.mode
                        onSelected: v => Share.mode = v
                    }
                }
                SettingRow {
                    label: "Sound"
                    description: "Travels in the same stream as the picture, so it cannot drift out of sync."
                    Toggle { checked: Share.withAudio; onToggled: v => Share.withAudio = v }
                }
                SettingRow {
                    visible: !Share.ready && Share.blockedBy !== ""
                    label: "Missing"
                    description: Share.blockedBy
                    Icon { name: "info"; size: 14; color: Theme.yellow }
                }
                Item {
                    width: parent.width; height: 38
                    Btn {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        icon: Share.serving ? "stop" : "play"
                        label: Share.serving ? "Stop sharing" : "Start sharing"
                        onClicked: Share.serving ? Share.stop() : Share.start()
                    }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        visible: Share.serving
                        spacing: Theme.spaceMd

                        // Address pill with click-to-copy
                        Row {
                            spacing: Theme.spaceSm
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: "address"
                                color: Theme.muted
                                font.family: Theme.font; font.pixelSize: Theme.fontXs
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                id: addrBadge
                                height: 30; width: addrContent.width + 16; radius: Theme.radiusSm
                                color: Theme.alpha(Theme.surface, 0.7)
                                border.width: 1
                                border.color: win.copiedAddr ? Theme.green : (addrMa.containsMouse ? Theme.accent : Theme.borderStrong)
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on border.color { ColorAnimation { duration: Theme.fast } }

                                Row {
                                    id: addrContent
                                    anchors.centerIn: parent; spacing: 6
                                    Text {
                                        id: addrTxt
                                        text: (Share.localIp || "127.0.0.1") + ":" + Share.port
                                        color: Theme.text
                                        font.family: Theme.fontMono; font.pixelSize: Theme.fontSm
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Icon {
                                        name: win.copiedAddr ? "check" : "copy"
                                        size: 13
                                        color: win.copiedAddr ? Theme.green : (addrMa.containsMouse ? Theme.text : Theme.muted)
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: addrMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Quickshell.execDetached(["wl-copy", "--", addrTxt.text])
                                        win.copiedAddr = true
                                        copyTimer.restart()
                                    }
                                }
                            }
                        }

                        // Code pill
                        Row {
                            spacing: Theme.spaceSm
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Share.pairCode !== ""
                            Text {
                                text: "code"
                                color: Theme.muted
                                font.family: Theme.font; font.pixelSize: Theme.fontXs
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                width: codeTxt.width + 20; height: 30; radius: Theme.radiusSm
                                color: Theme.alpha(Theme.accent, 0.14)
                                border.width: 1; border.color: Theme.alpha(Theme.accent, 0.4)
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    id: codeTxt
                                    anchors.centerIn: parent
                                    text: Share.pairCode
                                    color: Theme.accent
                                    font.family: Theme.fontMono; font.pixelSize: Theme.fontLg
                                    font.weight: Font.DemiBold; font.letterSpacing: 3
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border }

            // ── receive ────────────────────────────────────────────────
            Column {
                width: parent.width; spacing: Theme.spaceMd
                Text {
                    text: "RECEIVE  ·  the other machine's screen shows here"
                    color: Theme.muted
                    font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Use this when the other machine is the one sharing. Select an auto-discovered device below or enter its address manually."
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: Theme.fontSm
                }

                // Discovered nearby sharing devices on local Wi-Fi
                Column {
                    width: parent.width
                    spacing: Theme.spaceSm
                    visible: Share.nearbyHosts.length > 0

                    Row {
                        spacing: 8
                        Rectangle { width: 7; height: 7; radius: 4; color: Theme.green; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "DEVICES SHARING ON THIS WI-FI"
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold
                            font.letterSpacing: 1.1
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Repeater {
                        model: Share.nearbyHosts
                        delegate: Rectangle {
                            id: devCard
                            width: parent.width; height: 46; radius: Theme.radiusSm
                            color: devMa.containsMouse ? Theme.alpha(Theme.accent, 0.12) : Theme.alpha(Theme.surface, 0.6)
                            border.width: 1
                            border.color: (win.connectTarget === (modelData.ip + ":" + modelData.port)) ? Theme.accent : Theme.border
                            Behavior on color { ColorAnimation { duration: Theme.fast } }

                            Item {
                                anchors.fill: parent; anchors.margins: 10
                                Row {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                    Icon {
                                        name: "wifi"
                                        size: 16
                                        color: Theme.green
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                        Text {
                                            text: (modelData.name || "Praxis PC") + (modelData.is_self ? " (This PC)" : "")
                                            color: Theme.text
                                            font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold
                                        }
                                        Text {
                                            text: modelData.ip + ":" + modelData.port
                                            color: Theme.muted
                                            font.family: Theme.fontMono; font.pixelSize: Theme.fontXs
                                        }
                                    }
                                }
                                Btn {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    icon: "monitor"
                                    label: (win.connectTarget === (modelData.ip + ":" + modelData.port)) ? "Selected" : "Select"
                                    onClicked: {
                                        win.connectTarget = modelData.ip + ":" + modelData.port
                                        addr.text = win.connectTarget
                                        codeIn.forceActiveFocus()
                                    }
                                }
                            }

                            MouseArea {
                                id: devMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    win.connectTarget = modelData.ip + ":" + modelData.port
                                    addr.text = win.connectTarget
                                    codeIn.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                SettingRow {
                    label: Share.nearbyHosts.length > 0 ? "Or enter address manually" : "Show another machine's screen"
                    description: "Its address and the six-digit code, both shown on that machine when you start sharing there."
                    Row {
                        spacing: Theme.spaceSm
                        Rectangle {
                            width: 190; height: 30; radius: Theme.radiusSm
                            color: Theme.alpha(Theme.bg, 0.6)
                            border.width: 1
                            border.color: addr.activeFocus ? Theme.accent : Theme.border
                            Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                            TextInput {
                                id: addr
                                anchors.fill: parent; anchors.margins: 8
                                verticalAlignment: Text.AlignVCenter
                                color: Theme.text
                                font.family: Theme.fontMono; font.pixelSize: Theme.fontSm
                                onTextChanged: win.connectTarget = text
                                Keys.onPressed: (event) => {
                                    if ((event.modifiers & Qt.AltModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                        win.isFullscreen = !win.isFullscreen
                                        event.accepted = true
                                    }
                                }
                                onAccepted: {
                                    if (codeIn.text.length === 6 && text.trim()) {
                                        Share.connectTo(text.trim(), codeIn.text)
                                    } else {
                                        codeIn.forceActiveFocus()
                                    }
                                }
                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: !addr.text && !addr.activeFocus
                                    text: Share.localIp ? Share.localIp + ":5920" : "192.168.1.20:5920"
                                    color: Theme.muted
                                    font.family: Theme.fontMono; font.pixelSize: Theme.fontSm
                                }
                            }
                        }
                        Rectangle {
                            width: 96; height: 30; radius: Theme.radiusSm
                            color: Theme.alpha(Theme.bg, 0.6)
                            border.width: 1
                            border.color: codeIn.activeFocus ? Theme.accent : Theme.border
                            TextInput {
                                id: codeIn
                                anchors.fill: parent; anchors.margins: 8
                                verticalAlignment: Text.AlignVCenter
                                color: Theme.text
                                maximumLength: 6
                                inputMethodHints: Qt.ImhDigitsOnly
                                font.family: Theme.fontMono; font.pixelSize: Theme.fontSm; font.letterSpacing: 2
                                Keys.onPressed: (event) => {
                                    if ((event.modifiers & Qt.AltModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                        win.isFullscreen = !win.isFullscreen
                                        event.accepted = true
                                    }
                                }
                                onAccepted: {
                                    if (win.connectTarget.trim() && text.length === 6) {
                                        Share.connectTo(win.connectTarget.trim(), text)
                                    }
                                }
                                Text {
                                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                    visible: !codeIn.text && !codeIn.activeFocus
                                    text: "code"
                                    color: Theme.muted
                                    font.family: Theme.fontMono; font.pixelSize: Theme.fontSm
                                }
                            }
                        }
                        Btn {
                            icon: "monitor"; label: "Connect"
                            enabled: win.connectTarget.trim() !== "" && codeIn.text.length === 6
                            onClicked: Share.connectTo(win.connectTarget.trim(), codeIn.text)
                        }
                    }
                }
            }

            // ── live, only while it is ────────────────────────────────
            Column {
                width: parent.width; spacing: Theme.spaceSm
                visible: Share.serving
                Text {
                    text: "LIVE"
                    color: Theme.muted
                    font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Serving " + (Share.servingMon || "display") + " at "
                        + (Share.localIp ? Share.localIp + ":" + Share.port : ":" + Share.port)
                        + " (code: " + (Share.pairCode || "------") + ")  ·  "
                        + Share.clients + (Share.clients === 1 ? " viewer" : " viewers")
                        + (Share.withAudio ? "  ·  with sound" : "  ·  no sound")
                        + "\nOn the other PC, open this window and type the address and code in the Receive box above to show it fullscreen."
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: Theme.fontSm
                    lineHeight: 1.25
                }
            }
        }
    }
}
}
