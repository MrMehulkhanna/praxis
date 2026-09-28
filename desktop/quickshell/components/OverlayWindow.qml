import QtQuick
import Quickshell
import Quickshell.Wayland
import "root:/Config"
import "root:/Services"

// Full-screen overlay host on the focused monitor. Handles: scrim,
// click-outside / Escape to close, keyboard focus, and keeping the window
// alive until the close animation finishes (a hidden window would cut it).
PanelWindow {
    id: win
    property string name: ""                       // Shell.overlay value that opens this
    readonly property bool open: Shell.overlay === name
    property bool scrim: true
    property bool grabKeyboard: true
    default property alias content: slot.data
    signal opened()

    screen: Shell.activeScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell"
    WlrLayershell.keyboardFocus: open && grabKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: open || closing.running
    Timer { id: closing; interval: Theme.slow + 40 }
    onOpenChanged: { if (open) { closing.stop(); win.opened() } else closing.restart() }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: win.open && win.scrim ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: Shell.closeAll()
    }
    Item {
        id: slot
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Shell.closeAll()
    }
}
