import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "root:/Config"
import "root:/Services"
import "root:/components"

// Workspace overview — grid of all up-to-12 workspaces with live titles,
// window counts, and click-to-jump. Bound to Shell.overlay === "ws".
OverlayWindow {
    id: win
    name: "ws"
    scrim: true

    // fresh snapshot every open — we don't need a poll while it's just sitting
    property var workspaces: []
    onOpenedChanged: {
        if (open) {
            const raw = Hyprland.workspaces.values
                .filter(w => w.id > 0 && w.id <= 12)
                .sort((a, b) => a.id - b.id)
            // build a synthetic 1..12 slots so empty spots still render
            const map = {}
            for (const w of raw) map[w.id] = w
            const out = []
            for (let i = 1; i <= 12; i++) {
                out.push({
                    id: i,
                    ws: map[i] || null,
                    windowCount: map[i] ? map[i].toplevels.values.length : 0,
                    activeTitle: map[i] && map[i].lastwindow
                        ? (map[i].lastwindow.title || "").slice(0, 32) : "",
                    isActive: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === i,
                })
            }
            workspaces = out
        }
    }

    Item {
        anchors.centerIn: parent
        width: 4 * 220 + 3 * 14
        height: 3 * 150 + 2 * 14 + 46
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Behavior on scale   { NumberAnimation { duration: Theme.normal } }

        Text {
            id: hdr
            text: "Workspaces"
            color: Theme.text
            font.family: Theme.font; font.pixelSize: Theme.fontLg; font.weight: Font.Bold
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            anchors.top: hdr.bottom
            text: "click a tile to jump, esc to close"
            color: Theme.muted
            font.family: Theme.font; font.pixelSize: Theme.fontXs
            anchors.horizontalCenter: parent.horizontalCenter
        }

        GridLayout {
            id: grid
            anchors.top: hdr.bottom; anchors.topMargin: 32
            columns: 4
            rowSpacing: 14; columnSpacing: 14
            Repeater {
                model: win.workspaces
                Glass {
                    Layout.preferredWidth: 220; Layout.preferredHeight: 150
                    radius: Theme.radiusMd
                    color: modelData.isActive ? Theme.alpha(Theme.accent, 0.30)
                                              : cellMa.containsMouse ? Theme.alpha(Theme.text, 0.10)
                                                                     : Theme.alpha(Theme.text, 0.05)
                    border.width: 1
                    border.color: modelData.isActive ? Theme.accent : Theme.border
                    Behavior on color { ColorAnimation { duration: Theme.fast } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: modelData.id
                            color: modelData.isActive ? Theme.accent : Theme.text2
                            font.family: Theme.font; font.pixelSize: 44; font.weight: Font.Bold
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: modelData.windowCount + (modelData.windowCount === 1 ? " window" : " windows")
                            color: Theme.muted
                            font.family: Theme.fontMono; font.pixelSize: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: modelData.activeTitle
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: Theme.fontXs
                            elide: Text.ElideRight
                            width: 200
                            horizontalAlignment: Text.AlignHCenter
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        id: cellMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            HyprOpts.dispatch(`hl.dsp.focus({ workspace = ${modelData.id} })`)
                            Shell.closeAll()
                        }
                    }
                }
            }
        }
    }
}
