import QtQuick
import Quickshell
import "root:/Config"
import "root:/Services"
import "root:/components"

// Spotlight-style launcher. Type to search apps; ">" runs a PC command
// through the AI permission gate; "?" or no match asks the AI.
OverlayWindow {
    id: win
    name: "launcher"
    onOpened: { input.text = Shell.launcherPrefill; Shell.launcherPrefill = ""; list.currentIndex = 0; input.forceActiveFocus() }

    readonly property var actions: [
        { name: "Settings",     hint: "Open shell settings",  icon: "gear",  run: () => Shell.open("settings") },
        { name: "Lock screen",  hint: "hyprlock",             icon: "lock",  run: () => Power.lock() },
        { name: "Suspend",      hint: "Sleep now",            icon: "moon",  run: () => Power.suspend(), confirm: true },
        { name: "Reboot",       hint: "Restart the computer", icon: "refresh", run: () => Power.reboot(), confirm: true },
        { name: "Power off",    hint: "Shut down",            icon: "power", run: () => Power.poweroff(), confirm: true },
        { name: "Log out",      hint: "Exit Hyprland",        icon: "user",  run: () => Power.logout(), confirm: true },
    ]

    // keywords/categories come back as QStringList, not strings — String() normalises
    // both (and null) so a single bad field can't throw and kill the whole filter.
    function norm(v) { return v == null ? "" : String(v).toLowerCase() }

    function score(entry, q) {
        const n = norm(entry.name), g = norm(entry.genericName)
        const k = norm(entry.keywords) + " " + norm(entry.categories), c = norm(entry.comment)
        if (n === q) return 100
        if (n.startsWith(q)) return 80
        if (n.split(/\s+/).some(w => w.startsWith(q))) return 70
        if (n.includes(q)) return 50
        if (g.includes(q) || k.includes(q)) return 30
        if (c.includes(q)) return 10
        return 0
    }

    readonly property string query: input.text.trim()
    readonly property string mode: query.startsWith(">") ? "control" : query.startsWith("?") ? "ask" : "search"
    readonly property var results: {
        if (mode !== "search") return []
        const q = query.toLowerCase()
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay && e.name)
        let rows = []
        if (!q) {
            rows = apps.slice().sort((a, b) => a.name.localeCompare(b.name)).slice(0, 8).map(e => ({ kind: "app", entry: e, name: e.name, hint: e.genericName || e.comment || "" }))
        } else {
            const scored = apps.map(e => ({ s: score(e, q), e })).filter(x => x.s > 0).sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name))
            rows = scored.slice(0, 7).map(x => ({ kind: "app", entry: x.e, name: x.e.name, hint: x.e.genericName || x.e.comment || "" }))
            for (const a of actions) if (a.name.toLowerCase().includes(q)) rows.push({ kind: "action", action: a, name: a.name, hint: a.hint })
            rows.push({ kind: "ask", name: "Ask AI: " + query, hint: "Send to " + (Aios.selectedInfo ? Aios.selectedInfo.label : "AIOS") })
            rows.push({ kind: "control", name: "Control PC: " + query, hint: "Run through the permission gate" })
        }
        return rows
    }

    property int confirmIndex: -1

    function activate(i) {
        const r = results[i]
        if (!r) {
            if (mode === "control") { Aios.control(query.slice(1)); Shell.open("ai") }
            else if (mode === "ask") { Aios.send(query.slice(1)); Shell.open("ai") }
            return
        }
        if (r.kind === "app") { r.entry.execute(); Shell.closeAll() }
        else if (r.kind === "action") {
            if (r.action.confirm && confirmIndex !== i) { confirmIndex = i; return }
            r.action.run(); Shell.closeAll()
        }
        else if (r.kind === "ask") { Aios.send(query); Shell.open("ai") }
        else if (r.kind === "control") { Aios.control(query); Shell.open("ai") }
    }
    onQueryChanged: { confirmIndex = -1; list.currentIndex = 0 }

    Glass {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.18
        width: Math.min(640, parent.width - 80)
        height: 64 + (list.count ? list.contentHeight + 16 : (win.mode !== "search" ? 56 : 0))
        radius: Theme.radiusXl
        color: Theme.glassStrong
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Theme.easePop; easing.overshoot: Theme.popOvershoot } }
        Behavior on height { NumberAnimation { duration: Theme.fast; easing.type: Theme.easeMove } }

        MouseArea { anchors.fill: parent }   // swallow clicks so backdrop doesn't close

        // search field
        Item {
            id: field
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 64
            Icon {
                id: fieldIcon
                anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                name: win.mode === "control" ? "terminal" : win.mode === "ask" ? "sparkle" : "search"
                size: 20; color: win.mode === "search" ? Theme.text2 : Theme.accent
            }
            TextInput {
                id: input
                anchors { left: fieldIcon.right; leftMargin: 14; right: hintTxt.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Medium
                selectionColor: Theme.alpha(Theme.accent, 0.4)
                clip: true
                Text {
                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                    visible: !input.text
                    text: "Search apps  ·  > control PC  ·  ? ask AI"
                    color: Theme.muted; font: input.font
                }
                Keys.onDownPressed: list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1)
                Keys.onUpPressed: list.currentIndex = Math.max(0, list.currentIndex - 1)
                Keys.onReturnPressed: win.activate(list.currentIndex)
                Keys.onEnterPressed: win.activate(list.currentIndex)
                Keys.onTabPressed: list.currentIndex = (list.currentIndex + 1) % Math.max(1, list.count)
                Keys.onEscapePressed: Shell.closeAll()
            }
            Text {
                id: hintTxt
                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                text: win.mode === "control" ? "Enter ↵ run" : win.mode === "ask" ? "Enter ↵ ask" : ""
                color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs
            }
        }
        Rectangle {
            anchors { top: field.bottom; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
            height: 1; color: Theme.border; visible: list.count > 0 || win.mode !== "search"
        }

        // direct-mode hint row
        Item {
            anchors { top: field.bottom; left: parent.left; right: parent.right; margins: 8 }
            height: 48; visible: win.mode !== "search"
            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 12
                Icon { name: win.mode === "control" ? "terminal" : "sparkle"; size: 16; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: win.mode === "control"
                        ? "The AI turns this into one command. Safe commands run; anything else asks you first."
                        : "Sent to " + (Aios.selectedInfo ? Aios.selectedInfo.label : "the selected model") + " with relevant memory only."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: Theme.fontSm
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        ListView {
            id: list
            anchors { top: field.bottom; left: parent.left; right: parent.right; margins: 8; topMargin: 9 }
            height: contentHeight
            model: win.results
            interactive: false
            clip: true
            highlightMoveDuration: Theme.fast
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width; height: 44
                radius: Theme.radiusMd
                color: index === list.currentIndex ? Theme.alpha(Theme.accent, 0.18) : rowMa.containsMouse ? Theme.hover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Row {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 12
                    Item {
                        width: 26; height: 26; anchors.verticalCenter: parent.verticalCenter
                        Image {
                            anchors.fill: parent
                            visible: modelData.kind === "app"
                            source: modelData.kind === "app" ? Quickshell.iconPath(modelData.entry.icon, true) : ""
                            sourceSize: Qt.size(64, 64); smooth: true
                        }
                        Rectangle {
                            visible: modelData.kind === "app" && (parent.children[0].source == "" || parent.children[0].status === Image.Error)
                            anchors.fill: parent; radius: 7; color: Theme.surface3; border.width: 1; border.color: Theme.borderStrong
                            Text { anchors.centerIn: parent; text: modelData.name.slice(0, 1).toUpperCase(); color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold }
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: modelData.kind !== "app"
                            name: modelData.kind === "ask" ? "sparkle" : modelData.kind === "control" ? "terminal" : (modelData.action ? modelData.action.icon : "grid")
                            size: 18; color: modelData.kind === "app" ? Theme.text : Theme.accent
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: modelData.name
                            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontLg; font.weight: Font.Medium
                            elide: Text.ElideRight; width: list.width - 140
                        }
                        Text {
                            visible: text.length > 0
                            text: modelData.hint
                            color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontXs
                            elide: Text.ElideRight; width: list.width - 140
                        }
                    }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: win.confirmIndex === index ? "Enter again to confirm" : index === list.currentIndex ? "↵" : ""
                    color: win.confirmIndex === index ? Theme.yellow : Theme.muted
                    font.family: Theme.font; font.pixelSize: Theme.fontXs
                }
                MouseArea {
                    id: rowMa
                    anchors.fill: parent; hoverEnabled: true
                    onEntered: list.currentIndex = index
                    onClicked: win.activate(index)
                }
            }
        }
    }
}
