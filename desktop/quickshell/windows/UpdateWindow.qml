import QtQuick
import Quickshell
import "root:/Config"
import "root:/Services"
import "root:/components"

// System update — the same work praxis-update always did, with somewhere to
// watch it happen. Progress is the current section heading rather than a
// guessed percentage, because the script knows what it is doing and a fake
// bar would only be a lie that moves.
OverlayWindow {
    id: win
    name: "update"
    onOpened: Updates.checkRestart()

    component Btn: IconButton { implicitHeight: 30; padding: 10 }

    Glass {
        anchors.centerIn: parent
        width: 680
        height: Math.min(parent.height - 80, 520)
        radius: Theme.radiusXl
        elevation: 3

        Column {
            anchors.fill: parent
            anchors.margins: 26
            spacing: Theme.spaceLg

            // ── header ─────────────────────────────────────────────────
            Item {
                width: parent.width; height: 36
                Column {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: "System update"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold
                    }
                    Text {
                        text: Updates.running ? Updates.phase
                            : Updates.failed ? "something went wrong — the log is below"
                            : Updates.finished ? "up to date"
                            : "Pulls the desktop, tools and system packages from the repository."
                        color: Updates.failed ? Theme.red : (Updates.running ? Theme.accent : Theme.muted)
                        font.family: Theme.font; font.pixelSize: Theme.fontSm
                        elide: Text.ElideRight
                        width: 480
                    }
                }
                // a spinner, not a progress bar: honest about not knowing
                Rectangle {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    visible: Updates.running
                    width: 18; height: 18; radius: 9
                    color: "transparent"
                    border.width: 2; border.color: Theme.alpha(Theme.accent, 0.25)
                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: "transparent"
                        border.width: 2; border.color: "transparent"
                        Rectangle { width: 4; height: 4; radius: 2; color: Theme.accent; x: 7; y: -1 }
                        RotationAnimation on rotation {
                            running: Updates.running; loops: Animation.Infinite
                            from: 0; to: 360; duration: 1100
                        }
                    }
                }
            }

            // ── restart banner ─────────────────────────────────────────
            // Only here when it is true, and it says what needs it. A
            // reboot nag with no reason gets dismissed on reflex.
            Rectangle {
                width: parent.width
                height: Updates.restartNeeded ? banner.implicitHeight + 22 : 0
                visible: Updates.restartNeeded
                radius: Theme.radiusLg
                color: Theme.alpha(Theme.yellow, 0.12)
                border.width: 1; border.color: Theme.alpha(Theme.yellow, 0.4)
                Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Theme.easeMove } }

                Row {
                    id: banner
                    anchors.fill: parent; anchors.margins: 11
                    spacing: Theme.spaceMd
                    Icon { name: "refresh"; size: 16; color: Theme.yellow; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        width: parent.width - 220
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Restart to finish"
                            color: Theme.yellow
                            font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.DemiBold
                        }
                        Text {
                            text: "Updated and still running the old version: " + Updates.restartReason
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: Theme.fontXs
                            wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                    Row {
                        spacing: Theme.spaceSm
                        anchors.verticalCenter: parent.verticalCenter
                        Btn { icon: "refresh"; label: "Restart now"; onClicked: Updates.restartNow() }
                        Btn { icon: "x"; label: "Later"; onClicked: Updates.dismissRestart() }
                    }
                }
            }

            // ── log ────────────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: 260
                radius: Theme.radiusLg
                color: Theme.alpha(Theme.bg, 0.65)
                border.width: 1; border.color: Theme.border
                clip: true

                ListView {
                    id: logView
                    anchors.fill: parent; anchors.margins: 10
                    model: Updates.lines
                    spacing: 1
                    // follow the tail while it runs, but stop fighting the
                    // user the moment they scroll back to read something
                    property bool pinned: true
                    onMovementStarted: pinned = false
                    onCountChanged: if (pinned) positionViewAtEnd()
                    delegate: Text {
                        required property string modelData
                        width: logView.width
                        text: modelData
                        color: modelData.indexOf("==>") >= 0 ? Theme.accent
                             : (modelData.toLowerCase().indexOf("error") >= 0 ? Theme.red : Theme.text2)
                        font.family: Theme.fontMono; font.pixelSize: Theme.fontXs
                        wrapMode: Text.WrapAnywhere
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: Updates.lines.length === 0
                    text: Updates.running ? "starting…" : "nothing yet"
                    color: Theme.muted
                    font.family: Theme.font; font.pixelSize: Theme.fontSm
                }
                // let the user get back to following the tail
                Btn {
                    anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 8
                    visible: !logView.pinned && Updates.running
                    icon: "chevron-down"; label: "Follow"
                    onClicked: { logView.pinned = true; logView.positionViewAtEnd() }
                }
            }

            // ── actions ────────────────────────────────────────────────
            Item {
                width: parent.width; height: 32
                Btn {
                    anchors.left: parent.left
                    icon: Updates.running ? "refresh" : "refresh"
                    label: Updates.running ? "Updating…" : (Updates.finished ? "Check again" : "Update now")
                    enabled: !Updates.running
                    onClicked: Updates.start()
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "no password needed · runs praxis-update"
                    color: Theme.muted
                    font.family: Theme.font; font.pixelSize: Theme.fontXs
                }
            }
        }
    }
}
