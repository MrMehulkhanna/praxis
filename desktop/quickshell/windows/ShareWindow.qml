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
                SettingRow {
                    label: "Allow screen share"
                    description: Share.serving
                        ? "Advertising on local Wi-Fi. The other PC can discover this screen automatically."
                        : "Turn on to let another Praxis PC connect as a second display or mirror."
                    Toggle {
                        checked: Share.serving
                        onToggled: v => v ? Share.start() : Share.stop()
                    }
                }
                // Huge PIN and IP badge shown prominently while serving
                Rectangle {
                    visible: Share.serving
                    width: parent.width
                    height: pinCardCol.implicitHeight + 28
                    radius: Theme.radiusLg
                    color: Theme.alpha(Theme.surface, 0.7)
                    border.width: 1
                    border.color: Theme.alpha(Theme.accent, 0.4)

                    Column {
                        id: pinCardCol
                        anchors.fill: parent; anchors.margins: 14
                        spacing: 12

                        Row {
                            width: parent.width
                            spacing: Theme.spaceSm
                            Text {
                                text: "PAIRING PIN"
                                color: Theme.accent
                                font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.Bold; font.letterSpacing: 1.2
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item { width: 12; height: 1 }
                            Rectangle {
                                radius: Theme.radiusSm
                                color: Theme.alpha(Theme.accent, 0.15)
                                border.width: 1; border.color: Theme.alpha(Theme.accent, 0.4)
                                implicitHeight: 22
                                implicitWidth: ipBadgeTxt.implicitWidth + 16
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    id: ipBadgeTxt
                                    anchors.centerIn: parent
                                    text: "Address: " + (Share.localIp ? Share.localIp + ":" + Share.port : ":" + Share.port)
                                    color: Theme.text
                                    font.family: Theme.fontMono; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold
                                }
                            }
                        }

                        // Huge 4-digit PIN display
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12
                            Repeater {
                                model: (Share.pairCode || "----").split("")
                                Rectangle {
                                    width: 52; height: 60; radius: Theme.radiusSm
                                    color: Theme.alpha(Theme.bg, 0.8)
                                    border.width: 1; border.color: Theme.alpha(Theme.accent, 0.5)
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: Theme.accent
                                        font.family: Theme.fontMono; font.pixelSize: 32; font.weight: Font.Bold
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── host: who is watching, and what you can do about it ────
            Rectangle {
                visible: Share.serving
                width: parent.width
                height: hostCol.implicitHeight + 24
                radius: Theme.radiusLg
                color: Share.clients > 0 ? Theme.alpha(Theme.green, 0.10) : Theme.alpha(Theme.accent, 0.08)
                border.width: 1
                border.color: Share.clients > 0 ? Theme.alpha(Theme.green, 0.40) : Theme.alpha(Theme.accent, 0.30)
                Column {
                    id: hostCol
                    anchors.fill: parent; anchors.margins: 12
                    spacing: 10
                    Row {
                        spacing: 8
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: Share.clients > 0 ? Theme.green : Theme.yellow
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: Share.clients > 0 ? "Connected" : "Waiting"
                            color: Share.clients > 0 ? Theme.green : Theme.accent
                            font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.Bold; font.letterSpacing: 1.1
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: Share.clients > 0
                            ? "Connected — " + Share.clients + (Share.clients === 1 ? " viewer" : " viewers")
                              + ". Your extra screen is to the right of this one."
                            : "Waiting — open Share screen on the other PC and pick this one from the list."
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.fontSm
                    }
                    Row {
                        visible: Share.clients > 0
                        spacing: Theme.spaceSm
                        Btn { icon: "monitor"; label: "Send focused window there"; onClicked: Share.sendWindowThere() }
                        Btn { icon: "chevron-left"; label: "Bring all windows back"; onClicked: Share.bringBack() }
                        Btn { icon: "stop"; label: "Stop sharing"; onClicked: Share.stop() }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border }
            // ── viewer: what this PC is showing ───────────────────────
            Rectangle {
                visible: Share.viewing || Share.connectError !== ""
                width: parent.width
                height: viewCol.implicitHeight + 24
                radius: Theme.radiusLg
                color: Share.connectError !== "" ? Theme.alpha(Theme.red, 0.10) : Theme.alpha(Theme.green, 0.10)
                border.width: 1
                border.color: Share.connectError !== "" ? Theme.alpha(Theme.red, 0.40) : Theme.alpha(Theme.green, 0.40)
                Column {
                    id: viewCol
                    anchors.fill: parent; anchors.margins: 12
                    spacing: 10
                    Row {
                        spacing: 8
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: Share.connectError !== "" ? Theme.red : Theme.green
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: Share.connectError !== "" ? "Connection Error" : "Viewer Active"
                            color: Share.connectError !== "" ? Theme.red : Theme.green
                            font.family: Theme.font; font.pixelSize: Theme.fontXs; font.weight: Font.Bold; font.letterSpacing: 1.1
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: Share.connectError !== "" ? Share.connectError
                            : "Showing " + Share.viewTarget + " fullscreen. Super+C or Disconnect to stop."
                        color: Share.connectError !== "" ? Theme.red : Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.fontSm
                    }
                    Btn {
                        visible: Share.viewing
                        icon: "x"; label: "Disconnect"
                        onClicked: Share.disconnect()
                    }
                }
            }


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

                    Item {
                        width: parent.width; height: 30
                        Row {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
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
                        Btn {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            icon: "search"
                            label: Share.scanning ? "Scanning…" : "Scan"
                            onClicked: Share.scan()
                        }
                    }

                    Rectangle {
                        visible: Share.nearbyHosts.length === 0
                        width: parent.width; height: 42; radius: Theme.radiusSm
                        color: Theme.alpha(Theme.surface, 0.4)
                        border.width: 1; border.color: Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: "No sharing devices found yet — start sharing on the other PC, then Scan"
                            color: Theme.muted
                            font.family: Theme.font; font.pixelSize: Theme.fontSm
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
                    description: "Its address and the four-digit code, both shown on that machine when you start sharing there."
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
                                onTextChanged: {
                                    let t = text.trim()
                                    if (Share.localIp && Share.localIp.startsWith("10.225.") && t.startsWith("10.255.")) {
                                        t = "10.225." + t.slice(7)
                                    }
                                    win.connectTarget = t
                                }
                                Keys.onPressed: (event) => {
                                    if ((event.modifiers & Qt.AltModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                        win.isFullscreen = !win.isFullscreen
                                        event.accepted = true
                                    }
                                }
                                onAccepted: {
                                    let t = win.connectTarget.trim()
                                    if (codeIn.text.length === 4 && t) {
                                        Share.connectTo(t, codeIn.text)
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
                                maximumLength: 4
                                inputMethodHints: Qt.ImhDigitsOnly
                                font.family: Theme.fontMono; font.pixelSize: Theme.fontSm; font.letterSpacing: 2
                                Keys.onPressed: (event) => {
                                    if ((event.modifiers & Qt.AltModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                        win.isFullscreen = !win.isFullscreen
                                        event.accepted = true
                                    }
                                }
                                onAccepted: {
                                    if (win.connectTarget.trim() && text.length === 4) {
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
                            enabled: win.connectTarget.trim() !== "" && codeIn.text.length === 4
                            onClicked: Share.connectTo(win.connectTarget.trim(), codeIn.text)
                        }
                    }
                }

                SettingRow {
                    label: "Use this keyboard and mouse on the other PC (Experimental)"
                    description: "Control the remote machine using Deskflow input sharing."
                    Toggle {
                        checked: Share.inputControl
                        onToggled: v => {
                            Share.inputControl = v
                            if (!v && Share.inputSharing) {
                                Share.stopInput()
                            }
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
