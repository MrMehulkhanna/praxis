import QtQuick
import Quickshell
import "root:/State"
import "root:/Ui"

Column {
    spacing: 22
    Image { source: "file:///usr/share/icons/hicolor/scalable/apps/praxis.svg"; width: 64; height: 64; sourceSize: Qt.size(128, 128) }
    Column {
        spacing: 8
        Text { text: "Install Praxis Linux"; color: T.text; font.family: T.font; font.pixelSize: 30; font.weight: Font.Bold }
        Text {
            width: 560; wrapMode: Text.WordWrap
            text: "The desktop you are trying right now, on your own disk — next to Windows if you like. It takes about 10–20 minutes. Nothing changes until the very last step, and you see exactly what will happen first."
            color: T.text2; font.family: T.font; font.pixelSize: 15; lineHeight: 1.25
        }
    }
    Column {
        spacing: 10
        component Status: Row {
            property bool good: false
            property string text: ""
            property string bad: ""
            spacing: 10
            Rectangle { width: 22; height: 22; radius: 11; color: parent.good ? T.alpha(T.green, 0.2) : T.alpha(T.yellow, 0.2)
                Text { anchors.centerIn: parent; text: parent.parent.good ? "✓" : "!"; color: parent.parent.good ? T.green : T.yellow; font.pixelSize: 12; font.weight: Font.Bold } }
            Text { anchors.verticalCenter: parent.verticalCenter; text: parent.good ? parent.text : parent.bad; color: T.text; font.family: T.font; font.pixelSize: 14; width: 520; wrapMode: Text.WordWrap }
        }
        Status { good: Inst.online; text: "Connected to the internet"; bad: "Not online — connect to Wi-Fi (the installer downloads current packages)" }
        Status { good: !!Inst.probe && Inst.probe.uefi; text: "Started in UEFI mode"; bad: Inst.probe ? "Started in legacy BIOS mode — turn off CSM/Legacy in the firmware, then restart from the USB" : "Checking the firmware…" }
        Status { good: Inst.disks.length > 0; text: Inst.disks.length + (Inst.disks.length === 1 ? " disk found" : " disks found"); bad: Inst.probing ? "Looking at the disks…" : "No disk to install to was found" }
    }
    Row {
        spacing: 10
        Btn { visible: !Inst.online; text: "Connect to Wi-Fi"; onClicked: Quickshell.execDetached(["kitty", "--class", "praxis-wifi", "-e", "nmtui-connect"]) }
        Btn { text: "Use the text installer instead"; onClicked: Quickshell.execDetached(["kitty", "--class", "praxis-installer", "--title", "Install Praxis Linux (text)", "-e", "/usr/local/bin/praxis-install-window"]) }
    }
}
