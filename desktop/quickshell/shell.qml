//@ pragma UseQApplication
import QtQuick
import Quickshell
import "root:/Config"
import "root:/Services"
import "windows"

ShellRoot {
    // Ambient background layer — 3 drifting glow orbs, reacts to CPU/mem/time.
    Variants { model: Quickshell.screens; AmbientLayer {} }
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
    WidgetBoard {}
    WorkspaceOverview {}

    // singletons that must be alive from the start
    Component.onCompleted: { Shell.overlay; Aios.online; Notifs.count; Net.icon; Audio.icon; Power.profile; Wallpaper.files; HyprOpts.blur }
}
