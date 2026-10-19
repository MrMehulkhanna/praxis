//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/State"
import "root:/Ui"
import "pages"

// Praxis graphical installer: praxis-installer → quickshell -p <this dir>.
// Pages collect the answers; Inst runs praxis-install-engine with them.
ShellRoot {
    FloatingWindow {
        id: win
        title: "Install Praxis Linux"
        implicitWidth: 1000
        implicitHeight: 680
        color: T.bg

        property int page: 0
        readonly property var steps: ["Welcome", "Disk", "Apps", "You", "Check", "Install"]
        readonly property bool canNext:
            page === 0 ? Inst.online && !!Inst.probe && Inst.probe.uefi && Inst.disks.length > 0
          : page === 1 ? Inst.diskReady
          : page === 2 ? true
          : page === 3 ? Inst.youReady
          : false
        onPageChanged: if (page === 5 && Inst.stage === "idle") Inst.install()
        // for automated screenshots and UI tests: show a page (never the Install page —
        // installing always takes the button) and fill in example answers
        IpcHandler {
            target: "installer"
            function page(n: int): void { if (n >= 0 && n <= 4 && Inst.stage === "idle") win.page = n }
            function mode(m: string): void { Inst.setMode(m) }
            function example(): void { Inst.fullName = "Alex Doe"; Inst.password = "praxis-test"; Inst.password2 = "praxis-test"; Inst.toggleApp("office") }
        }
        // reopened while an installation runs: straight to its progress
        Connections { target: Inst; function onResumedChanged() { if (Inst.resumed) win.page = 5 } }

        // ── sidebar ──
        Rectangle {
            id: side
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: 230
            color: T.surface
            Column {
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 26 }
                spacing: 6
                Row {
                    spacing: 10; bottomPadding: 26
                    Image { source: "file:///usr/share/icons/hicolor/scalable/apps/praxis.svg"; width: 28; height: 28; sourceSize: Qt.size(64, 64) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Praxis"; color: T.text; font.family: T.font; font.pixelSize: 18; font.weight: Font.Bold }
                }
                Repeater {
                    model: win.steps
                    Row {
                        required property var modelData
                        required property int index
                        spacing: 12; height: 38
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26; height: 26; radius: 13
                            color: index < win.page ? T.alpha(T.green, 0.2) : index === win.page ? T.accent : T.surface3
                            Text {
                                anchors.centerIn: parent
                                text: index < win.page ? "✓" : index + 1
                                color: index < win.page ? T.green : index === win.page ? T.accentInk : T.muted
                                font.family: T.font; font.pixelSize: 12; font.weight: Font.Bold
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData
                            color: index === win.page ? T.text : index < win.page ? T.text2 : T.muted
                            font.family: T.font; font.pixelSize: 14; font.weight: index === win.page ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }
            Text {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 26 }
                wrapMode: Text.WordWrap
                text: "Nothing on your disks changes until you press Install on the Check page."
                color: T.muted; font.family: T.font; font.pixelSize: 12
            }
        }

        // ── page ──
        Flickable {
            id: flick
            anchors { top: parent.top; bottom: nav.top; left: side.right; right: parent.right; margins: 40; bottomMargin: 10 }
            contentHeight: loader.item ? loader.item.implicitHeight + 10 : 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Loader {
                id: loader
                width: flick.width
                sourceComponent: [welcome, disk, apps, you, summary, run][win.page]
                onLoaded: flick.contentY = 0
            }
            Component { id: welcome; Welcome {} }
            Component { id: disk; Disk {} }
            Component { id: apps; Apps {} }
            Component { id: you; You {} }
            Component { id: summary; Summary {} }
            Component { id: run; Run {} }
        }

        // ── navigation ──
        Rectangle {
            id: nav
            anchors { bottom: parent.bottom; left: side.right; right: parent.right }
            height: 72
            color: T.bg
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: T.border }
            Row {
                anchors { right: parent.right; rightMargin: 40; verticalCenter: parent.verticalCenter }
                spacing: 10
                Btn { visible: win.page > 0 && win.page < 5; text: "Back"; onClicked: win.page-- }
                Btn {
                    visible: win.page < 4
                    primary: true; text: "Continue"; enabled: win.canNext
                    onClicked: win.page++
                }
                Btn {
                    visible: win.page === 4
                    danger: Inst.mode === "wipe" || Inst.mode === "partition"
                    primary: !(Inst.mode === "wipe" || Inst.mode === "partition")
                    text: "Install"
                    onClicked: win.page = 5
                }
                Btn { visible: win.page === 5 && Inst.stage === "failed"; text: "Back to the start"; onClicked: { Inst.stage = "idle"; Inst.scan(); win.page = 1 } }
            }
        }
    }
}
