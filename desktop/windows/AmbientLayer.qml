import QtQuick
import Quickshell
import Quickshell.Wayland
import "root:/Config"
import "root:/Services"

// Praxis Ambient — three drifting glow orbs behind everything.
// Purely decorative, click-through, GPU-cheap.  Each orb picks up a
// different system channel:
//   1. hue drifts with time-of-day
//   2. size pulses with CPU load
//   3. brightness follows memory pressure
// so the desktop feels alive but stays legible.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "praxis-ambient"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { }   // input pass-through

    // one Sys consumer while this is on screen
    Component.onCompleted: Sys.active++
    Component.onDestruction: Sys.active--

    // canvas
    Item {
        anchors.fill: parent
        visible: Settings.ambientEnabled === undefined ? true : Settings.ambientEnabled

        // Time-of-day hue: 0..360 across a 24h cycle (shifted so night is cool)
        readonly property real todHue: {
            const d = new Date()
            const h = d.getHours() + d.getMinutes()/60
            return (h / 24 * 360 + 200) % 360
        }
        readonly property real cpuLoad: Math.min(1, Sys.cpu / 100)
        readonly property real memLoad: Math.min(1, Sys.mem / 100)

        // three orbs, each with a slow independent drift
        Repeater {
            model: [
                { seed: 0.0,  baseX: 0.18, baseY: 0.28, r: 240, colH: 0   },
                { seed: 0.33, baseX: 0.78, baseY: 0.35, r: 300, colH: 120 },
                { seed: 0.66, baseX: 0.45, baseY: 0.80, r: 340, colH: 240 },
            ]
            Rectangle {
                readonly property real drift: (root.driftT + modelData.seed) * 2 * Math.PI
                x: parent.width  * (modelData.baseX + 0.09 * Math.cos(drift))       - width/2
                y: parent.height * (modelData.baseY + 0.06 * Math.sin(drift * 1.3)) - height/2
                width:  modelData.r * (0.85 + 0.35 * parent.cpuLoad)
                height: width
                radius: width / 2
                opacity: 0.32 + 0.28 * parent.memLoad
                // hue rotates with time of day around the orb's base offset
                color: Qt.hsla(((parent.todHue + modelData.colH) % 360) / 360, 0.55, 0.55, 1.0)
                // soft-glow: cheap blur emulation via layered opacity + scale
                scale: 1.0
                Rectangle {
                    anchors.fill: parent; anchors.margins: -60
                    radius: (parent.width + 120) / 2
                    color: parent.color
                    opacity: 0.35
                }
                Rectangle {
                    anchors.fill: parent; anchors.margins: -120
                    radius: (parent.width + 240) / 2
                    color: parent.color
                    opacity: 0.15
                }
                Behavior on width  { NumberAnimation { duration: 1200; easing.type: Easing.OutCubic } }
                Behavior on color  { ColorAnimation  { duration: 6000 } }
                Behavior on opacity{ NumberAnimation { duration: 2400 } }
            }
        }

        // drift clock — one shared 0..1 phase, wraps every 60 s
        property real driftT: 0
        Timer {
            interval: 40; running: parent.visible; repeat: true
            onTriggered: parent.driftT = (parent.driftT + 40/60000) % 1
        }
    }
}
