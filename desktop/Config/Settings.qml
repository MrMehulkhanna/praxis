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
    property alias dockAllScreens: s.dockAllScreens
    property alias dockFavorites:  s.dockFavorites
    property alias barStats:       s.barStats
    property alias wallpaper:      s.wallpaper
    property alias clock24h:       s.clock24h
    property alias showSeconds:    s.showSeconds

    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter() }

        JsonAdapter {
            id: s
            property string profile: "Normal"          // Normal | Development | Cyber Lab | Presentation
            property string accent: "auto"             // "auto" or "#rrggbb"
            property real   transparency: 0.60         // glass alpha
            property int    radius: 18
            property real   animations: 1.0            // 0 = off, 1 = normal, 1.5 = slow & dramatic
            property bool   blur: true
            property int    dockIconSize: 44
            property bool   dockAutoHide: false
            // when true (legacy), dock hides while a workspace has a fullscreen window;
            // set false to keep the dock visible even on fullscreen apps.
            property bool   dockHideOnFullscreen: false
            property bool   dockAllScreens: false
            property list<string> dockFavorites: [
                "google-chrome", "kitty", "thunar", "aios"
            ]
            property string barStats: "auto"           // auto | on | off
            property string wallpaper: ""
            property bool   clock24h: false
            property bool   showSeconds: false
        }
    }

    // effective values derived from profile
    readonly property bool statsVisible:
        barStats === "on" ? true
      : barStats === "off" ? false
      : (profile === "Development" || profile === "Cyber Lab")
}
