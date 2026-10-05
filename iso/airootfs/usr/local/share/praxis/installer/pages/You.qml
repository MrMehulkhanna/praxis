import QtQuick
import "root:/State"
import "root:/Ui"

Column {
    spacing: 16
    Text { text: "About you"; color: T.text; font.family: T.font; font.pixelSize: 24; font.weight: Font.Bold }
    Grid {
        columns: 2; columnSpacing: 20; rowSpacing: 14
        Field { label: "Your name"; placeholder: "Alex Doe"; text: Inst.fullName; onTextChanged: Inst.fullName = text
                bad: /[:,=]/.test(text); hint: bad ? "no : , or =" : "" }
        Field { label: "User name"; text: Inst.userName; onTextChanged: { if (text !== Inst.userName) { Inst.userEdited = true; Inst.userName = text } }
                bad: Inst.userError !== ""; hint: Inst.userError || "used to log in and for your home folder" }
        Field { label: "Password"; password: true; text: Inst.password; onTextChanged: Inst.password = text; bad: Inst.passError !== "" && Inst.password.length < 4 }
        Field { label: "Password again"; password: true; text: Inst.password2; onTextChanged: Inst.password2 = text
                bad: Inst.passError !== "" && Inst.password2 !== ""; hint: Inst.passError }
        Field { label: "Computer name"; text: Inst.hostName; onTextChanged: { if (text !== Inst.hostName) { Inst.hostEdited = true; Inst.hostName = text } }
                bad: Inst.hostError !== ""; hint: Inst.hostError || "how this PC shows up on the network" }
        Pick { label: "Time zone"; model: Inst.timezones; current: Inst.timezone; onChosen: v => Inst.timezone = v }
        Pick { label: "Keyboard layout"; model: Inst.layouts; current: Inst.xkb; onChosen: v => Inst.xkb = v }
        Pick { label: "Language and formats"; model: Inst.locales; current: Inst.locale; onChosen: v => Inst.locale = v }
    }
    Check {
        width: 660
        text: "Ask for my password when the computer starts"
        sub: Inst.lockAtStart ? "The desktop starts behind the lock screen." : "Logs you in automatically — anyone who turns the computer on gets in."
        checked: Inst.lockAtStart
        onToggled: v => Inst.lockAtStart = v
    }
}
