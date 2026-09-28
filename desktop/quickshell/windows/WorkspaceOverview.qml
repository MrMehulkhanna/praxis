import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "root:/Config"
import "root:/Services"
import "root:/components"

// Workspace overview (SUPER+TAB) — all twelve workspaces as a 4×3 grid.
// Each tile shows the window count and up to three window titles; click a
// tile to jump there. Empty workspaces still render so the grid is stable.
OverlayWindow {
    id: win
    name: "ws"

    // Rebuilt on every open: the list is only needed while visible, and a
    // snapshot avoids re-laying out twelve tiles on every Hyprland event.
    property var slots: []
    onOpened: {
        const byId = {}
        for (const w of Hyprland.workspaces.values) if (w.id > 0 && w.id <= 12) byId[w.id] = w
        const focusedId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
        const out = []
        for (let i = 1; i <= 12; i++) {
            const ws = byId[i]
            const wins = ws && ws.toplevels ? ws.toplevels.values : []
            out.push({
                id: i,
                exists: !!ws,
                focused: i === focusedId,
                urgent: !!(ws && ws.urgent),
                count: wins.length,
                titles: wins.slice(0, 3).map(t => t.title || "untitled"),
            })
        }
        slots = out
    }

    Column {
        anchors.centerIn: parent
        spacing: 18
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Theme.easePop; easing.overshoot: Theme.popOvershoot } }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Workspaces"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: Theme.fontXl; font.weight: Font.Bold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Click to jump  ·  Esc to close"
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: Theme.fontXs
            }
        }

        GridLayout {
            columns: 4
            rowSpacing: 14
            columnSpacing: 14

            Repeater {
                model: win.slots
                Glass {
                    id: tile
                    required property var modelData
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 138
                    radius: Theme.radiusMd
                    color: modelData.focused ? Theme.alpha(Theme.accent, 0.28)
                         : tileMa.containsMouse ? Theme.alpha(Theme.text, 0.10)
                         : Theme.glass
                    borderColor: modelData.focused ? Theme.accent
                               : modelData.urgent ? Theme.red
                               : Theme.border
                    opacity: modelData.exists || tileMa.containsMouse ? 1 : 0.55
                    Behavior on color { ColorAnimation { duration: Theme.fast } }

                    Text {
                        anchors { top: parent.top; left: parent.left; topMargin: 10; leftMargin: 14 }
                        text: tile.modelData.id
                        color: tile.modelData.focused ? Theme.accent : Theme.text
                        font.family: Theme.font; font.pixelSize: 30; font.weight: Font.Bold
                    }
                    Text {
                        anchors { top: parent.top; right: parent.right; topMargin: 16; rightMargin: 14 }
                        text: tile.modelData.count === 0 ? "empty"
                            : tile.modelData.count + (tile.modelData.count === 1 ? " window" : " windows")
                        color: Theme.muted
                        font.family: Theme.fontMono; font.pixelSize: 10
                    }
                    Column {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
                        spacing: 2
                        Repeater {
                            model: tile.modelData.titles
                            Text {
                                required property string modelData
                                width: parent.width
                                elide: Text.ElideRight
                                text: "· " + modelData
                                color: Theme.text2
                                font.family: Theme.font; font.pixelSize: Theme.fontXs
                            }
                        }
                    }

                    MouseArea {
                        id: tileMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            HyprOpts.dispatch(`hl.dsp.focus({ workspace = ${tile.modelData.id} })`)
                            Shell.closeAll()
                        }
                    }
                }
            }
        }
    }
}
