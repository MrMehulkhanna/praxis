import QtQuick
import Quickshell
import Quickshell.Io
import "root:/State"
import "root:/Ui"

Column {
    spacing: 20
    Text {
        text: Inst.stage === "done" ? "Praxis is installed" : Inst.stage === "failed" ? "The installation stopped" : "Installing Praxis"
        color: T.text; font.family: T.font; font.pixelSize: 26; font.weight: Font.Bold
    }
    Text {
        width: 620; wrapMode: Text.WordWrap
        color: Inst.stage === "failed" ? T.red : T.text2; font.family: T.font; font.pixelSize: 14
        text: Inst.stage === "done" ? "Restart and take out the USB drive. Praxis starts with a menu that also lists Windows and any other system.\nIf the computer goes straight to Windows instead, press its boot-menu key while it starts (often F12, F9 or Esc) and pick Praxis — or move Praxis to the top of the boot order in the firmware settings."
            : Inst.stage === "failed" ? Inst.failText + "\nWhatever was not reached was left as it was. The full log is /var/log/praxis-install.log."
            : "This takes 10–20 minutes, mostly downloading. You can keep using the live desktop meanwhile."
    }
    Column {
        visible: Inst.stage === "running" || Inst.stage === "done"
        spacing: 10
        Rectangle {
            width: 620; height: 10; radius: 5; color: T.surface3
            Rectangle { width: parent.width * Inst.percent / 100; height: parent.height; radius: 5; color: Inst.stage === "done" ? T.green : T.accent
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } }
        }
        Text { text: Inst.percent + " % · " + Inst.stepText; color: T.text2; font.family: T.mono; font.pixelSize: 12; width: 620; elide: Text.ElideRight }
    }
    // the last lines of the installer's log
    Rectangle {
        width: 620; height: 230; radius: T.r; color: T.surface; border.width: 1; border.color: T.border
        visible: Inst.stage !== "idle"
        clip: true
        Text {
            id: logText
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            color: T.muted; font.family: T.mono; font.pixelSize: 11; wrapMode: Text.WrapAnywhere
        }
        Process {
            id: tail
            command: ["tail", "-n", "14", "/var/log/praxis-install.log"]
            stdout: StdioCollector { onStreamFinished: logText.text = this.text.trim() }
        }
        Timer { interval: 1500; repeat: true; running: Inst.stage === "running"; triggeredOnStart: true; onTriggered: if (!tail.running) tail.running = true }
        Connections { target: Inst; function onStageChanged() { if (!tail.running) tail.running = true } }
    }
    Row {
        spacing: 10
        Btn { visible: Inst.stage === "done"; primary: true; text: "Restart now"; onClicked: Quickshell.execDetached(["systemctl", "reboot"]) }
        Btn { visible: Inst.stage === "failed"; text: "Open the log"; onClicked: Quickshell.execDetached(["kitty", "-e", "less", "+G", "/var/log/praxis-install.log"]) }
    }
}
