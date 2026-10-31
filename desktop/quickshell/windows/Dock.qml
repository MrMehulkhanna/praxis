import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "root:/Config"
import "root:/Services"
import "root:/components"

// Floating glass dock: favourites + running apps, hover magnification,
// running indicator, auto-hide for fullscreen windows.
PanelWindow {
    id: dock
    required property var modelData
    screen: modelData

    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell"

    readonly property var hyprMon: Hyprland.monitorFor(screen)
    readonly property bool fullscreenHere: !!(hyprMon && hyprMon.activeWorkspace && hyprMon.activeWorkspace.hasFullscreen)
    readonly property bool hideForFullscreen: fullscreenHere && Settings.dockHideOnFullscreen
    visible: Settings.dockVisible && !hideForFullscreen

    // Visible window count on current monitor's active workspace
    readonly property var activeWs: hyprMon ? hyprMon.activeWorkspace : null
    readonly property int activeWindowCount: {
        if (!activeWs) return 0
        const tls = ToplevelManager.toplevels.values
        let c = 0
        for (const t of tls) {
            if (!t.minimized) c++
        }
        return c
    }

    // Is the pointer on the dock? HoverHandlers are passive, so they stay
    // "hovered" while the pointer is over an icon. The MouseAreas used before
    // lost the hover to the icon's own MouseArea, so the dock slid away under
    // the cursor 350 ms after you pointed at an icon — mid-click.
    readonly property bool pointerOn: dockHover.hovered || edgeHover.hovered
    readonly property bool wantHidden:
        !Settings.dockVisible ||
        (Settings.dockAutoHide && !pointerOn && Shell.overlay !== "launcher") || hideForFullscreen
    property bool hidden: false
    onWantHiddenChanged: {
        if (hideForFullscreen) {
            hideDebounce.stop()
            revealDwell.stop()
            hidden = true
        } else if (wantHidden) {
            revealDwell.stop()
            hideDebounce.restart()
        } else {
            hideDebounce.stop()
            // brushing the screen edge on the way to something else doesn't pop it up
            if (hidden && edgeHover.hovered) revealDwell.restart()
            else hidden = false
        }
    }
    Component.onCompleted: hidden = wantHidden
    Timer { id: hideDebounce; interval: 400; onTriggered: dock.hidden = dock.wantHidden }
    Timer { id: revealDwell;  interval: 35;  onTriggered: if (!dock.wantHidden) dock.hidden = false }

    readonly property int  iconSize: Theme.dockIcon
    readonly property int  padding: 8
    readonly property int  windowGap: Theme.dockWindowGap

    implicitWidth: glass.width + 40
    implicitHeight: iconSize + padding * 2 + Theme.dockMargin + windowGap + 28 + Settings.dockOffset   // room for magnified icons + labels + elevation
    // An auto-hiding dock floats over windows. When docked, reserve space with a generous gap
    // so windows never touch or crowd the dock.
    exclusiveZone: (!Settings.dockVisible || Settings.dockAutoHide || hideForFullscreen)
        ? 0
        : iconSize + padding * 2 + Theme.dockMargin + windowGap + Settings.dockOffset

    // Only the dock itself (and, while hidden, a responsive full-width strip at the screen edge)
    // takes the mouse; the rest of this window lets clicks through to the apps underneath.
    mask: Region {
        item: Settings.dockVisible ? glass : null
        Region { item: (Settings.dockVisible && dock.hidden) ? edge : null }
    }

    // ── model: favourites first, then running apps not already pinned ──
    // byId/heuristicLookup are exact and can miss (case, .desktop suffix, StartupWMClass),
    // which used to leave entry == null and make clicking the icon do nothing at all.
    // Fall back to scanning the real entry list before giving up.
    function entryFor(appId) {
        if (!appId) return null
        const direct = DesktopEntries.byId(appId) || DesktopEntries.heuristicLookup(appId)
        if (direct) return direct
        const want = normId(appId)
        const apps = DesktopEntries.applications.values
        for (const a of apps) if (normId(a.id) === want) return a
        for (const a of apps) if (normId(a.startupClass) === want) return a
        for (const a of apps) if ((a.name || "").toLowerCase() === want) return a
        return null
    }
    function normId(s) { return (s || "").toLowerCase().replace(/\.desktop$/, "") }

    // last resort so a dock click is never a no-op: launch the id as a command
    function launch(m) {
        if (m.entry) { m.entry.execute(); return }
        Quickshell.execDetached(["bash", "-lc", `gtk-launch ${m.appId} 2>/dev/null || exec ${m.appId}`])
    }

    readonly property var items: {
        const apps = DesktopEntries.applications.values   // dependency: re-evaluate once entries load
        const out = []
        const seen = {}
        const tls = ToplevelManager.toplevels.values
        for (const fav of Settings.dockFavorites) {
            const entry = entryFor(fav)
            const key = normId(entry ? entry.id : fav)
            const running = tls.filter(t => normId(t.appId) === key || (entry && normId(t.appId) === normId(entry.startupClass)))
            out.push({ key, entry, appId: fav, running, pinned: true })
            seen[key] = true
        }
        for (const t of tls) {
            const key = normId(t.appId)
            if (seen[key]) continue
            seen[key] = true
            const entry = entryFor(t.appId)
            out.push({ key, entry, appId: t.appId, running: tls.filter(x => normId(x.appId) === key), pinned: false })
        }
        return out
    }

    // reveal strip: full-width 12 px bottom hot zone across monitor
    Item {
        id: edge
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 12
        enabled: !dock.hideForFullscreen
        HoverHandler { id: edgeHover; enabled: !dock.hideForFullscreen }
    }

    Glass {
        id: glass
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dock.hidden ? -(height + Theme.dockMargin + 4) : Theme.dockMargin + Settings.dockOffset
        Behavior on anchors.bottomMargin { NumberAnimation { duration: Theme.slow; easing.type: Theme.easeMove } }
        width: row.width + dock.padding * 2
        height: dock.iconSize + dock.padding * 2
        radius: Theme.radiusXl
        color: Theme.glassStrong

        HoverHandler { id: dockHover }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6

            Repeater {
                model: dock.items
                Item {
                    id: slot
                    required property var modelData
                    required property int index
                    readonly property bool hov: ma.containsMouse
                    readonly property bool isRunning: modelData.running.length > 0
                    readonly property bool isActive: modelData.running.some(t => t.activated)
                    width: dock.iconSize; height: dock.iconSize

                    Image {
                        id: img
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: slot.hov ? dock.iconSize * 1.28 : dock.iconSize
                        height: width
                        anchors.bottomMargin: slot.hov ? 6 : 0
                        source: slot.modelData.entry && slot.modelData.entry.icon ? Quickshell.iconPath(slot.modelData.entry.icon, true)
                              : Quickshell.iconPath(slot.modelData.appId, true)
                        sourceSize: Qt.size(128, 128)
                        smooth: true; mipmap: true
                        opacity: slot.isRunning || slot.modelData.pinned ? 1 : 0.9
                        scale: ma.pressed ? 0.9 : 1
                        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Theme.easePop; easing.overshoot: Theme.popOvershoot } }
                        Behavior on anchors.bottomMargin { NumberAnimation { duration: Theme.normal; easing.type: Theme.easePop; easing.overshoot: Theme.popOvershoot } }
                        Behavior on scale { NumberAnimation { duration: Theme.fast } }
                    }

                    // placeholder when no icon exists
                    Rectangle {
                        visible: img.source == "" || img.status === Image.Error
                        anchors.fill: img; radius: width * 0.24
                        color: Theme.surface3; border.width: 1; border.color: Theme.borderStrong
                        Text { anchors.centerIn: parent; text: (slot.modelData.entry ? slot.modelData.entry.name : slot.modelData.appId).slice(0, 1).toUpperCase(); color: Theme.text; font.family: Theme.font; font.pixelSize: parent.width * 0.42; font.weight: Font.Bold }
                    }

                    // running indicator
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom; anchors.topMargin: 3
                        width: slot.isActive ? 14 : 5; height: 4; radius: 2
                        color: slot.isActive ? Theme.accent : Theme.text2
                        visible: slot.isRunning
                        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Theme.easeMove } }
                    }

                    // label above on hover
                    Glass {
                        visible: opacity > 0
                        opacity: slot.hov ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.top; anchors.bottomMargin: 22
                        width: lbl.implicitWidth + 20; height: 26
                        radius: Theme.radiusSm; color: Theme.glassStrong; shadowStrength: 0.5
                        Text {
                            id: lbl
                            anchors.centerIn: parent
                            text: slot.modelData.entry ? slot.modelData.entry.name : slot.modelData.appId
                            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSm; font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onClicked: mouse => {
                            const m = slot.modelData
                            if (mouse.button === Qt.MiddleButton) { dock.launch(m); return }
                            if (mouse.button === Qt.RightButton) {
                                // toggle pin
                                const favs = Settings.dockFavorites.slice()
                                const i = favs.findIndex(f => dock.normId(f) === m.key || (m.entry && dock.normId(f) === dock.normId(m.entry.id)))
                                if (i >= 0) favs.splice(i, 1); else favs.push(m.entry ? m.entry.id : m.appId)
                                Settings.dockFavorites = favs
                                return
                            }
                            if (m.running.length === 0) { dock.launch(m); return }
                            // cycle windows of this app; focus the first non-active
                            const active = m.running.find(t => t.activated)
                            if (!active) { m.running[0].activate(); return }
                            if (m.running.length > 1) {
                                const i = m.running.indexOf(active)
                                m.running[(i + 1) % m.running.length].activate()
                            } else active.minimized = !active.minimized
                        }
                    }
                }
            }

            // separator + launcher button
            Rectangle { width: 1; height: dock.iconSize * 0.6; color: Theme.borderStrong; anchors.verticalCenter: parent.verticalCenter }
            Item {
                width: dock.iconSize; height: dock.iconSize
                Rectangle {
                    anchors.centerIn: parent
                    width: dock.iconSize * (lma.containsMouse ? 1.05 : 0.9); height: width; radius: width * 0.28
                    color: Shell.overlay === "launcher" ? Theme.accent : Theme.alpha(Theme.text, 0.08)
                    border.width: 1; border.color: Theme.border
                    Behavior on width { NumberAnimation { duration: Theme.fast } }
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Icon { anchors.centerIn: parent; name: "grid"; size: parent.width * 0.5; color: Shell.overlay === "launcher" ? Theme.onAccent : Theme.text }
                }
                MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; onClicked: Shell.toggle("launcher") }
            }
        }
    }
}
