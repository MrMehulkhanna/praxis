import QtQuick
import "root:/State"

// The disk as a bar: one block per partition and unallocated region, drawn to
// scale. With a plan it previews the result — Windows getting smaller, the
// new Praxis partition in purple.
Item {
    id: bar
    property var disk: null
    property string mode: ""
    property string shrinkPart: ""
    property real praxisMiB: 0
    property string targetPart: ""
    implicitHeight: 92
    implicitWidth: 600

    function gib(m) { return m >= 10240 ? Math.round(m / 1024) + " GB" : (m / 1024).toFixed(1) + " GB" }
    function roleName(p) {
        switch (p.role) {
            case "esp": return "EFI"
            case "msr": return "Reserved"
            case "recovery": return "Recovery"
            case "windows": case "windows-encrypted":
                return "Windows" + (p.label && p.label.toLowerCase() !== "windows" ? " (" + p.label + ")" : "")
            case "linux": return p.label || "Linux"
            case "swap": return "Swap"
            default: return p.label || p.fstype || "Partition"
        }
    }
    function colorOf(kind) {
        switch (kind) {
            case "windows": case "windows-encrypted": return "#4f8ef7"
            case "linux": return T.green
            case "praxis": return T.purple
            case "free": return "transparent"
            default: return T.surface3
        }
    }
    readonly property var segments: {
        if (!disk) return []
        if (mode === "wipe") return [{ kind: "esp", name: "EFI", size: 1024 }, { kind: "praxis", name: "Praxis", size: disk.size_mib - 1024 }]
        const segs = []
        for (const p of disk.partitions) segs.push({ kind: p.role, name: roleName(p), size: p.size_mib, start: p.start_mib, path: p.path })
        for (const f of disk.free) if (f.size_mib >= 1024) segs.push({ kind: "free", name: "Free", size: f.size_mib, start: f.start_mib })
        segs.sort((a, b) => a.start - b.start)
        const out = []
        let usedFree = false
        const largest = disk.free.reduce((m, f) => f.size_mib > m ? f.size_mib : m, 0)
        for (const s of segs) {
            if (mode === "alongside" && s.path === shrinkPart) {
                out.push(Object.assign({}, s, { size: s.size - praxisMiB, name: s.name + " · smaller" }))
                out.push({ kind: "praxis", name: "Praxis", size: praxisMiB })
            } else if (mode === "free" && s.kind === "free" && s.size === largest && !usedFree) {
                usedFree = true
                out.push({ kind: "praxis", name: "Praxis", size: s.size })
            } else if (mode === "partition" && s.path === targetPart) {
                out.push({ kind: "praxis", name: "Praxis (formatted)", size: s.size })
            } else out.push(s)
        }
        return out
    }
    readonly property real total: segments.reduce((t, s) => t + s.size, 0) || 1

    Row {
        id: row
        width: parent.width; height: 54
        spacing: 3
        Repeater {
            model: bar.segments
            Rectangle {
                required property var modelData
                readonly property real w: Math.max(6, (bar.width - 3 * (bar.segments.length - 1)) * modelData.size / bar.total)
                width: w; height: row.height; radius: 9
                color: bar.colorOf(modelData.kind)
                border.width: modelData.kind === "free" ? 1 : 0
                border.color: T.borderStrong
                Behavior on width { NumberAnimation { duration: T.normal; easing.type: Easing.OutCubic } }
                Column {
                    anchors.centerIn: parent
                    visible: parent.w > 70
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; color: modelData.kind === "free" || modelData.kind === "esp" || modelData.kind === "msr" || modelData.kind === "recovery" ? T.text2 : T.accentInk; font.family: T.font; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight; width: Math.min(implicitWidth, parent.parent.w - 12) }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: bar.gib(modelData.size); color: modelData.kind === "free" || modelData.kind === "esp" || modelData.kind === "msr" || modelData.kind === "recovery" ? T.muted : T.alpha(T.accentInk, 0.75); font.family: T.font; font.pixelSize: 11 }
                }
            }
        }
    }
    Text {
        anchors { top: row.bottom; topMargin: 10; left: parent.left }
        text: bar.disk ? bar.disk.path + " · " + bar.disk.model + " · " + bar.gib(bar.disk.size_mib) + (bar.disk.label ? "" : " · no partition table") : ""
        color: T.muted; font.family: T.font; font.pixelSize: 12
    }
}
