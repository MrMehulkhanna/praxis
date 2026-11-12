pragma Singleton
import QtQuick
import Quickshell

// Single source of truth for every visual token. Components never hardcode
// colours, radii, durations or font sizes — they read them from here.
Singleton {
    id: theme

    // ── palette ────────────────────────────────────────────────────────
    readonly property color bg:        "#0b0d12"
    readonly property color surface:   "#12161e"
    readonly property color surface2:  "#181d27"
    readonly property color surface3:  "#1f2532"

    readonly property color text:      "#edf2f7"
    readonly property color text2:     "#9ca8b8"
    readonly property color muted:     "#657184"

    readonly property color blue:      "#7aa2f7"
    readonly property color purple:    "#bb9af7"
    readonly property color green:     "#8bd5a1"
    readonly property color yellow:    "#e8c77b"
    readonly property color red:       "#ef8f9d"
    readonly property color teal:      "#7dcfff"

    // accent follows the active profile unless the user pinned one in Settings
    readonly property color accent: {
        const pinned = Settings.accent
        if (pinned && pinned !== "auto") return pinned
        switch (Settings.profile) {
            case "Development":  return purple
            case "Cyber Lab":    return green
            case "Presentation": return text
            default:             return blue
        }
    }
    readonly property color onAccent: Settings.profile === "Presentation" ? bg : "#0b0d12"

    // ── glass ──────────────────────────────────────────────────────────
    // Hyprland blurs the layer behind us (layerrule blur,quickshell), so
    // these only need low alpha to read as frosted glass.
    readonly property real  glassAlpha: Settings.transparency
    readonly property color glass:       Qt.rgba(0.06, 0.07, 0.10, glassAlpha)
    readonly property color glassStrong: Qt.rgba(0.05, 0.06, 0.09, Math.min(1, glassAlpha + 0.30))
    readonly property color border:      Qt.rgba(1, 1, 1, 0.08)
    readonly property color borderStrong:Qt.rgba(1, 1, 1, 0.14)
    readonly property color highlight:   Qt.rgba(1, 1, 1, 0.10)   // 1px top edge light
    readonly property color hover:       Qt.rgba(1, 1, 1, 0.07)
    readonly property color pressed:     Qt.rgba(1, 1, 1, 0.12)
    readonly property color shadow:      Qt.rgba(0, 0, 0, 0.45)

    // ── elevation ──────────────────────────────────────────────────────
    // One shadow token made every surface sit on the same plane. Three
    // levels give the stack an order the eye can read: the bar and dock rest
    // just above the wallpaper, panels float over windows, modals sit on top
    // of everything. Pair each with its matching blur radius and y-offset.
    readonly property color elev1:       Qt.rgba(0, 0, 0, 0.28)   // bar, dock
    readonly property color elev2:       Qt.rgba(0, 0, 0, 0.42)   // panels, popovers
    readonly property color elev3:       Qt.rgba(0, 0, 0, 0.58)   // modals, dialogs
    readonly property int   elev1Blur:   12
    readonly property int   elev2Blur:   24
    readonly property int   elev3Blur:   40
    readonly property int   elev1Y:      2
    readonly property int   elev2Y:      6
    readonly property int   elev3Y:      12
    readonly property color scrim:       Qt.rgba(0, 0, 0, 0.35)

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ── geometry ───────────────────────────────────────────────────────
    readonly property int radiusSm:  8
    readonly property int radiusMd:  12
    readonly property int radiusLg:  Settings.radius
    readonly property int radiusXl:  Settings.radius + 6

    readonly property int spaceXs: 4
    readonly property int spaceSm: 8
    readonly property int spaceMd: 12
    readonly property int spaceLg: 16
    readonly property int spaceXl: 24

    // 1440x810 logical is a small canvas; 38 + 8 spent 5.7 % of the height on
    // the bar alone. 34 + 6 still clears a 13 px label with room to spare.
    readonly property int barHeight:   34
    readonly property int barMargin:   6
    readonly property int dockIcon:    Settings.dockIconSize
    readonly property int dockMargin:  10
    readonly property int dockWindowGap: 16

    // ── type ───────────────────────────────────────────────────────────
    readonly property string font:     "Adwaita Sans"
    readonly property string fontMono: "Adwaita Mono"
    readonly property int fontXs:    11
    readonly property int fontSm:    12
    readonly property int fontMd:    13
    readonly property int fontLg:    15
    readonly property int fontXl:    18
    readonly property int fontTitle: 22

    // ── motion ─────────────────────────────────────────────────────────
    // multiplier lets Settings scale all motion (0 = instant)
    readonly property real  motion:  Settings.animations
    readonly property int   fast:    Math.round(120 * motion)
    readonly property int   normal:  Math.round(200 * motion)
    readonly property int   slow:    Math.round(320 * motion)
    // OutQuint: most of the move happens in the first frames, then a long
    // soft landing — reads as fast and fluid at 60 and 120 Hz alike
    readonly property int   easeMove: Easing.OutQuint
    readonly property int   easePop:  Easing.OutBack
    readonly property real  popOvershoot: 0.9      // a hint of overshoot, not a bounce
}
