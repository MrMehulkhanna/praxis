import QtQuick
import "root:/State"
import "root:/Ui"

Column {
    spacing: 16
    Text { text: "Ready to install"; color: T.text; font.family: T.font; font.pixelSize: 24; font.weight: Font.Bold }
    PartBar {
        width: 640
        disk: Inst.disk; mode: Inst.mode
        shrinkPart: Inst.opt("alongside").part || ""; praxisMiB: Inst.praxisGiB * 1024; targetPart: Inst.targetPart
    }
    Rectangle {
        width: 640; height: what.implicitHeight + 28; radius: T.r
        color: Inst.mode === "wipe" || Inst.mode === "partition" ? T.alpha(T.red, 0.1) : T.alpha(T.accent, 0.08)
        border.width: 1; border.color: Inst.mode === "wipe" || Inst.mode === "partition" ? T.alpha(T.red, 0.5) : T.alpha(T.accent, 0.4)
        Text {
            id: what
            anchors { fill: parent; margins: 14 }
            wrapMode: Text.WordWrap
            color: T.text; font.family: T.font; font.pixelSize: 14; lineHeight: 1.2
            text: !Inst.disk ? "" :
                  Inst.mode === "alongside" ? "Windows' drive (" + Inst.opt("alongside").part + ") gets " + Math.round(Inst.praxisGiB) + " GB smaller and Praxis goes into that space. Windows keeps all its files; it checks its drive once the next time it starts — that's normal."
                : Inst.mode === "free" ? "Praxis goes into the unallocated space on " + Inst.disk.path + ". Nothing else on the disk changes."
                : Inst.mode === "partition" ? Inst.targetPart + " is formatted — everything on it is erased. The other partitions stay as they are."
                : "Everything on " + Inst.disk.path + " (" + Inst.disk.model + ") is erased."
        }
    }
    Grid {
        columns: 2; columnSpacing: 24; rowSpacing: 8
        component K: Text { color: T.muted; font.family: T.font; font.pixelSize: 13 }
        component V: Text { color: T.text; font.family: T.font; font.pixelSize: 13; width: 460; wrapMode: Text.WordWrap }
        K { text: "File system" }   V { text: Inst.fs === "btrfs" ? "btrfs, with a snapshot before every update" : "ext4" }
        K { text: "You" }           V { text: Inst.fullName + " · " + Inst.userName + " on “" + Inst.hostName + "”" }
        K { text: "Time zone" }     V { text: Inst.timezone + " · keyboard " + Inst.xkb + " · " + Inst.locale }
        K { text: "At start-up" }   V { text: Inst.lockAtStart ? "asks for your password" : "logs in automatically" }
        K { text: "Extra apps" }    V { text: Inst.apps.length ? Inst.bundles.filter(b => Inst.apps.indexOf(b.id) >= 0).map(b => b.title).join(", ") : "none" }
        K { text: "Boot menu" }     V { text: "Praxis, plus every other system found on this PC (Windows, …)" }
    }
}
