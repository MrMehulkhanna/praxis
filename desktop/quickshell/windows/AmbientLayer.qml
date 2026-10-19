import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "root:/Config"
import "root:/Services"

// Ambient layer — three soft radial glows drifting slowly behind all windows.
//
//   hue      follows the time of day (cool at night, warm by evening)
//   size     breathes with CPU load
//   opacity  follows memory pressure
//
// Cost control: this surface sits under blurred windows, so every repaint
// makes Hyprland re-blur them. The drift is therefore stepped at 8 fps (the
// motion is ~6 px/s, so steps are sub-pixel), and it freezes entirely on
// battery or while a fullscreen window covers this monitor.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom          // above the wallpaper, below windows
    WlrLayershell.namespace: "praxis-ambient"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}                                // fully click-through

    // a live (video) wallpaper brings its own motion — don't stack the orbs on it
    visible: Settings.ambientEnabled && !Wallpaper.isLive

    readonly property var hyprMon: Hyprland.monitorFor(screen)
    readonly property bool coveredByFullscreen: !!(hyprMon && hyprMon.activeWorkspace && hyprMon.activeWorkspace.hasFullscreen)
    readonly property bool animate: visible && !UPower.onBattery && !coveredByFullscreen

    // shared drift phase, 0..1 over 60 s
    property real phase: 0
    Timer {
        interval: 125
        running: root.animate
        repeat: true
        onTriggered: root.phase = (root.phase + 0.125 / 60) % 1
    }

    // Hold a Sys stats reference only while animating. Idempotent, so it can't
    // double-count no matter which of these handlers fires first.
    property bool sysCounted: false
    function syncSys() {
        if (animate && !sysCounted) { Sys.active++; sysCounted = true }
        else if (!animate && sysCounted) { Sys.active = Math.max(0, Sys.active - 1); sysCounted = false }
    }
    onAnimateChanged: syncSys()
    Component.onCompleted: syncSys()
    Component.onDestruction: if (sysCounted) Sys.active = Math.max(0, Sys.active - 1)

    SystemClock { id: clock; precision: SystemClock.Minutes }
    // 0..360; the +200 offset puts deep blues at midnight and warm hues at dusk
    readonly property real dayHue: {
        const d = clock.date
        return ((d.getHours() + d.getMinutes() / 60) / 24 * 360 + 200) % 360
    }
    readonly property real cpuLoad: Math.min(1, Sys.cpu / 100)
    readonly property real memLoad: Math.min(1, Sys.mem / 100)

    Repeater {
        model: [
            { seed: 0.00, bx: 0.20, by: 0.30, r: 260, dh: 0 },
            { seed: 0.33, bx: 0.78, by: 0.36, r: 320, dh: 110 },
            { seed: 0.66, bx: 0.46, by: 0.78, r: 360, dh: 230 },
        ]

        Item {
            id: orb
            required property var modelData
            readonly property real t: (root.phase + modelData.seed) * 2 * Math.PI
            readonly property real radius: modelData.r * (0.9 + 0.25 * root.cpuLoad)
            property real hue: (root.dayHue + modelData.dh) % 360
            Behavior on hue { NumberAnimation { duration: 8000; easing.type: Easing.InOutSine } }

            width: radius * 2
            height: radius * 2
            x: root.width  * (modelData.bx + 0.08 * Math.cos(t))       - radius
            y: root.height * (modelData.by + 0.06 * Math.sin(t * 1.3)) - radius
            opacity: 0.55 + 0.35 * root.memLoad
            Behavior on width { NumberAnimation { duration: 1500; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 3000 } }

            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: orb.width / 2; centerY: orb.height / 2
                        centerRadius: orb.width / 2
                        focalX: orb.width / 2; focalY: orb.height / 2
                        GradientStop { position: 0.00; color: Qt.hsla(orb.hue / 360, 0.70, 0.62, 0.42) }
                        GradientStop { position: 0.45; color: Qt.hsla(orb.hue / 360, 0.70, 0.58, 0.16) }
                        GradientStop { position: 1.00; color: Qt.hsla(orb.hue / 360, 0.70, 0.55, 0.00) }
                    }
                    startX: 0; startY: orb.height / 2
                    PathArc { x: orb.width; y: orb.height / 2; radiusX: orb.width / 2; radiusY: orb.height / 2 }
                    PathArc { x: 0;         y: orb.height / 2; radiusX: orb.width / 2; radiusY: orb.height / 2 }
                }
            }
        }
    }
}
