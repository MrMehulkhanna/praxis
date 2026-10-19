import QtQuick
import "root:/State"
import "root:/Ui"

Column {
    id: page
    spacing: 18
    Text { text: "Where should Praxis go?"; color: T.text; font.family: T.font; font.pixelSize: 24; font.weight: Font.Bold }

    // disk tabs
    Row {
        spacing: 8
        visible: Inst.disks.length > 1
        Repeater {
            model: Inst.disks
            Rectangle {
                required property var modelData
                required property int index
                height: 36; width: dl.implicitWidth + 28; radius: 18
                color: index === Inst.diskIndex ? T.alpha(T.accent, 0.18) : dm.containsMouse ? T.hover : T.surface
                border.width: 1; border.color: index === Inst.diskIndex ? T.alpha(T.accent, 0.7) : T.border
                Text { id: dl; anchors.centerIn: parent; text: modelData.model + " · " + Math.round(modelData.size_mib / 1024) + " GB" + (modelData.has_windows ? " · Windows" : ""); color: T.text; font.family: T.font; font.pixelSize: 13 }
                MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; onClicked: Inst.diskIndex = index }
            }
        }
    }

    PartBar {
        width: 640
        disk: Inst.disk
        mode: Inst.mode
        shrinkPart: Inst.opt("alongside").part || ""
        praxisMiB: Inst.praxisGiB * 1024
        targetPart: Inst.targetPart
    }

    Column {
        spacing: 10
        Choice {
            width: 640
            title: "Next to Windows"
            sub: "Windows' drive gets smaller and keeps all its files. You pick Praxis or Windows each time the computer starts."
            why: Inst.opt("alongside").reason
            possible: Inst.opt("alongside").possible
            selected: Inst.mode === "alongside"
            onPicked: Inst.setMode("alongside")
            Column {
                width: parent.width; spacing: 6; topPadding: 8
                Row {
                    spacing: 12
                    Text { text: "Praxis gets " + Math.round(Inst.praxisGiB) + " GB"; color: T.text; font.family: T.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { text: "Windows keeps " + Math.round((Inst.opt("alongside").part_size_mib || 0) / 1024 - Inst.praxisGiB) + " GB"; color: T.muted; font.family: T.font; font.pixelSize: 14 }
                }
                Item {
                    width: parent.width; height: 28
                    readonly property real lo: (Inst.opt("alongside").min_praxis_mib || 30720) / 1024
                    readonly property real hi: (Inst.opt("alongside").max_praxis_mib || 30720) / 1024
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: T.surface3 }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: knob.x + knob.width / 2; height: 6; radius: 3; color: T.purple }
                    Rectangle {
                        id: knob
                        width: 20; height: 20; radius: 10; color: T.text; anchors.verticalCenter: parent.verticalCenter
                        x: (parent.width - width) * (parent.hi > parent.lo ? (Inst.praxisGiB - parent.lo) / (parent.hi - parent.lo) : 0)
                    }
                    MouseArea {
                        anchors.fill: parent
                        function set(mx) { const f = Math.max(0, Math.min(1, mx / width)); Inst.praxisGiB = Math.round(parent.lo + f * (parent.hi - parent.lo)) }
                        onPressed: m => set(m.x)
                        onPositionChanged: m => { if (pressed) set(m.x) }
                    }
                }
            }
        }
        Choice {
            width: 640
            title: "In the free space"
            sub: Math.round((Inst.opt("free").size_mib || 0) / 1024) + " GB of the disk is unallocated. Nothing else on it changes."
            why: Inst.opt("free").reason || ""
            possible: Inst.opt("free").possible
            selected: Inst.mode === "free"
            onPicked: Inst.setMode("free")
        }
        Choice {
            width: 640
            title: "In a partition I choose"
            sub: "Advanced — the partition is formatted; everything on it is erased."
            why: Inst.opt("partition").reason || ""
            possible: Inst.opt("partition").possible
            selected: Inst.mode === "partition"
            onPicked: Inst.setMode("partition")
            Flow {
                width: parent.width; spacing: 8; topPadding: 8
                Repeater {
                    model: Inst.opt("partition").candidates || []
                    Btn { required property var modelData; text: modelData; primary: Inst.targetPart === modelData; onClicked: Inst.targetPart = modelData }
                }
            }
        }
        Choice {
            width: 640
            danger: true
            title: "Erase the whole disk"
            sub: "Everything on " + (Inst.disk ? Inst.disk.path : "the disk") + " — every partition and file — is deleted."
            why: Inst.opt("wipe").reason || ""
            possible: Inst.opt("wipe").possible
            selected: Inst.mode === "wipe"
            onPicked: Inst.setMode("wipe")
            Check { width: parent.width; text: "I understand: erase " + (Inst.disk ? Inst.disk.path : ""); checked: Inst.wipeConfirmed; onToggled: v => Inst.wipeConfirmed = v }
        }
    }

    Row {
        spacing: 10
        Text { anchors.verticalCenter: parent.verticalCenter; text: "File system"; color: T.text2; font.family: T.font; font.pixelSize: 13; font.weight: Font.DemiBold }
        Btn { text: "btrfs + snapshots (recommended)"; primary: Inst.fs === "btrfs"; onClicked: Inst.fs = "btrfs" }
        Btn { text: "ext4"; primary: Inst.fs === "ext4"; onClicked: Inst.fs = "ext4" }
        Btn { text: Inst.probing ? "Scanning…" : "Scan again"; enabled: !Inst.probing; onClicked: Inst.scan() }
    }
    Text {
        visible: Inst.fs === "btrfs"
        width: 640; wrapMode: Text.WordWrap
        text: "Every update makes a snapshot first. If one ever breaks something, pick the snapshot from the boot menu and you're back."
        color: T.muted; font.family: T.font; font.pixelSize: 12
    }
}
