//@ pragma UseQApplication
import QtQuick
import Quickshell
import "root:/Config"
import "root:/Services"
import "windows"

ShellRoot {
    Variants { model: Quickshell.screens; TopBar {} }
    Variants {
        model: Settings.dockAllScreens ? Quickshell.screens : [Quickshell.screens[0]]
        Dock {}
    }
    Launcher {}
    ControlCenter {}
    AiPanel {}
    SettingsWindow {}
    ActivityPanel {}

    // singletons that must be alive from the start
    Component.onCompleted: { Shell.overlay; Aios.online; Notifs.count; Net.icon; Audio.icon; Power.profile; Wallpaper.files; HyprOpts.blur }
}
