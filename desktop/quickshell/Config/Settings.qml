pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// User preferences, persisted as JSON. Every property here is bound to a
// real control in the Settings window and takes effect immediately.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.config/quickshell/settings.json"

    // proxies so the rest of the shell can write `Settings.profile = ...`
    property alias profile:        s.profile
    property alias accent:         s.accent
    property alias transparency:   s.transparency
    property alias radius:         s.radius
    property alias animations:     s.animations
    property alias blur:           s.blur
    property alias dockIconSize:   s.dockIconSize
    property alias dockAutoHide:   s.dockAutoHide
    property alias dockHideOnFullscreen: s.dockHideOnFullscreen
    property alias dockVisible:    s.dockVisible
    property alias ambientEnabled: s.ambientEnabled
    property alias dockAllScreens: s.dockAllScreens
    property alias dockFavorites:  s.dockFavorites
    property alias barStats:       s.barStats
    property alias wallpaper:      s.wallpaper
    property alias liveOnBattery:  s.liveOnBattery
    property alias autoSaver:      s.autoSaver
    property alias idleMode:       s.idleMode
    property alias clock24h:       s.clock24h
    property alias showSeconds:    s.showSeconds
    property alias sleepTimeout:   s.sleepTimeout   // minutes before auto-sleep; 0 = never
    property alias touchGestures:         s.touchGestures         // 3-finger swipe for workspace switching
    property alias dockOffset:            s.dockOffset            // px to raise dock above bottom edge (0 = default)
    property alias touchpadSensitivity:   s.touchpadSensitivity   // -1.0 to 1.0 (0 = default 1:1 speed)
    property alias touchpadScrollFactor:  s.touchpadScrollFactor  // 0.2 to 2.0 (1.0 = default)
    property alias touchpadNaturalScroll: s.touchpadNaturalScroll // true = reverse / natural scrolling
    property alias touchpadTapToClick:    s.touchpadTapToClick    // true = tap to click
    property alias touchpadTapAndDrag:    s.touchpadTapAndDrag    // true = tap and drag

    // true once settings.json has been read (or found missing): services that
    // act on a saved choice at startup wait for this instead of racing the load
    property bool ready: false

    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoaded: root.ready = true
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); root.ready = true }

        JsonAdapter {
            id: s
            property string profile: "Normal"          // Normal | Development | Cyber Lab | Presentation
            property string accent: "auto"             // "auto" or "#rrggbb"
            property real   transparency: 0.60         // glass alpha
            property int    radius: 18
            property real   animations: 1.0            // 0 = off, 1 = normal, 1.5 = slow & dramatic
            property bool   blur: true
            property int    dockIconSize: 44
            property bool   dockAutoHide: true
            // when true, dock hides while a workspace has a fullscreen window
            property bool   dockHideOnFullscreen: true
            property bool   dockVisible: true          // false = dock fully hidden (saves bottom space on laptop)
            property bool   ambientEnabled: true       // 3 drifting glow orbs on the background
            property bool   dockAllScreens: false
            property var dockFavorites: [
                "firefox", "kitty", "thunar"
            ]
            property string barStats: "auto"           // auto | on | off
            property string wallpaper: ""
            property bool   liveOnBattery: false       // keep a live (video) wallpaper playing on battery
            property bool   autoSaver: true            // Battery saver on battery, off on the charger
            property string idleMode: "screenoff"      // off | oled | screenoff — hypridle profile
            property bool   clock24h: false
            property bool   showSeconds: false
            property int    sleepTimeout: 20           // minutes before auto-sleep; 0 = never
            property bool   touchGestures: true        // 3-finger swipe for workspace switching
            property int    dockOffset: 0              // px to raise dock above bottom edge (0 = flush)
            property real   touchpadSensitivity: 0.0   // -1.0 to 1.0 (0 = default raw speed)
            property real   touchpadScrollFactor: 1.0  // 0.2 to 2.0 (1.0 = standard speed)
            property bool   touchpadNaturalScroll: false // natural scrolling
            property bool   touchpadTapToClick: true   // tap to click
            property bool   touchpadTapAndDrag: true   // tap and drag
        }
    }

    // effective values derived from profile: visible by default unless user sets barStats to "off"
    readonly property bool statsVisible: barStats === "off" ? false : true
}
