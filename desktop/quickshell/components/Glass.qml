import QtQuick
import "root:/Config"

// Frosted glass surface: layered shadow, translucent body, hairline border
// and a 1px light edge on top. Hyprland blurs whatever is behind.
//
// `elevation` says how far above the wallpaper this surface sits, and the
// shadow follows from it: 1 for things attached to a screen edge (bar,
// dock), 2 for panels floating over windows, 3 for modals. Depth is what
// stops a flat compositor reading as paint on glass — a surface at
// elevation 3 casts a wider, softer, lower shadow than one at 1, and the
// eye uses that to order the stack without being told.
Item {
    id: root
    property real  radius: Theme.radiusLg
    property color color: Theme.glass
    property color borderColor: Theme.border
    property bool  shadow: true
    property int   elevation: 2
    property real  shadowStrength: 1.0
    default property alias content: inner.data

    readonly property color _tint: elevation <= 1 ? Theme.elev1 : elevation === 2 ? Theme.elev2 : Theme.elev3
    readonly property int   _blur: elevation <= 1 ? Theme.elev1Blur : elevation === 2 ? Theme.elev2Blur : Theme.elev3Blur
    readonly property int   _dy:   elevation <= 1 ? Theme.elev1Y : elevation === 2 ? Theme.elev2Y : Theme.elev3Y

    // Two stacked rectangles stand in for a blur: a wide faint one for the
    // ambient falloff, a tight darker one for contact. Cheap, no shader.
    Rectangle {
        visible: root.shadow
        anchors.fill: parent
        anchors.margins: -Math.round(root._blur * 0.5)
        anchors.topMargin: -Math.round(root._blur * 0.5) + root._dy
        radius: root.radius + Math.round(root._blur * 0.5)
        color: Theme.alpha(root._tint, 0.30 * root.shadowStrength)
        z: -2
    }
    Rectangle {
        visible: root.shadow
        anchors.fill: parent
        anchors.margins: -Math.round(root._blur * 0.18)
        anchors.topMargin: -Math.round(root._blur * 0.18) + Math.round(root._dy * 0.5)
        radius: root.radius + Math.round(root._blur * 0.18)
        color: Theme.alpha(root._tint, 0.55 * root.shadowStrength)
        z: -1
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: root.radius
        color: root.color
        border.width: 1
        border.color: root.borderColor

        // top edge highlight — reads as light catching the leading edge
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
            anchors.leftMargin: root.radius; anchors.rightMargin: root.radius
            height: 1
            color: Theme.highlight
        }
    }

    Item { id: inner; anchors.fill: parent }
}
