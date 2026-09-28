pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "root:/Config"

// Night-light / blue-light filter via a Hyprland screen shader.
// State persists in Settings and is re-applied on startup, so the shader
// never lingers as a ghost tint after a shell restart.
Singleton {
    id: root
    property alias enabled: s.eyeComfortOn
    property alias intensity: s.eyeComfortIntensity
    readonly property string shaderPath: Quickshell.env("HOME") + "/.config/hypr/shaders/blue-light.frag"

    // persisted state
    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/quickshell/eyecomfort.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter() }
        JsonAdapter {
            id: s
            property bool eyeComfortOn: false
            property real eyeComfortIntensity: 0.5
        }
    }

    Timer { id: debounce; interval: 150; onTriggered: root.apply() }
    onIntensityChanged: if (enabled) debounce.restart()
    onEnabledChanged: apply()

    function apply() {
        if (enabled) {
            // Gentle curve: even at intensity 1.0 this is a comfortable warm white
            // rather than the deep orange the old 0.7/0.3 coefficients produced.
            const b = (1.0 - intensity * 0.45).toFixed(3)
            const g = (1.0 - intensity * 0.16).toFixed(3)
            const frag = `#version 300 es
precision mediump float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;
void main() {
    vec4 c = texture(tex, v_texcoord);
    c.b = c.b * ${b};
    c.g = c.g * ${g};
    fragColor = c;
}`
            Quickshell.execDetached(["bash", "-c",
                `mkdir -p "$(dirname '${shaderPath}')" && cat > '${shaderPath}' <<'FRAG'\n${frag}\nFRAG\nhyprctl eval 'hl.config({ decoration = { screen_shader = "${shaderPath}" } })'`])
        } else {
            // empty string is the correct way to clear a Hyprland screen shader
            Quickshell.execDetached(["hyprctl", "eval", 'hl.config({ decoration = { screen_shader = "" } })'])
        }
    }

    function toggle() { enabled = !enabled }
    // re-assert the persisted state on startup (clears any ghost shader)
    Component.onCompleted: apply()
}
