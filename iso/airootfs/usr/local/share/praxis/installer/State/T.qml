pragma Singleton
import QtQuick
import Quickshell

// Installer palette — the same tokens as the Praxis desktop (Config/Theme.qml).
Singleton {
    readonly property color bg:       "#0b0d12"
    readonly property color surface:  "#12161e"
    readonly property color surface2: "#181d27"
    readonly property color surface3: "#1f2532"
    readonly property color text:     "#edf2f7"
    readonly property color text2:    "#9ca8b8"
    readonly property color muted:    "#657184"
    readonly property color accent:   "#7aa2f7"
    readonly property color accentInk: "#0b0d12"
    readonly property color purple:   "#bb9af7"
    readonly property color green:    "#8bd5a1"
    readonly property color yellow:   "#e8c77b"
    readonly property color red:      "#ef8f9d"
    readonly property color teal:     "#7dcfff"
    readonly property color border:   Qt.rgba(1, 1, 1, 0.08)
    readonly property color borderStrong: Qt.rgba(1, 1, 1, 0.14)
    readonly property color hover:    Qt.rgba(1, 1, 1, 0.06)
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    readonly property string font: "Adwaita Sans"
    readonly property string mono: "Adwaita Mono"
    readonly property int r: 14
    readonly property int fast: 120
    readonly property int normal: 220
}
