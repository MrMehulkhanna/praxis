pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// PipeWire default sink/source. Event-driven — no polling.
Singleton {
    id: root

    readonly property var sink:   Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source] }

    readonly property real volume:  sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted:   sink && sink.audio ? sink.audio.muted : false
    readonly property real micVolume: source && source.audio ? source.audio.volume : 0
    readonly property bool micMuted:  source && source.audio ? source.audio.muted : false
    readonly property string sinkName:   sink ? (sink.description || sink.nickname || sink.name || "Output") : "No output"
    readonly property string sourceName: source ? (source.description || source.nickname || source.name || "Input") : "No input"

    readonly property string icon: muted || volume <= 0.001 ? "volume-mute"
                                 : volume < 0.34 ? "volume-low"
                                 : volume < 0.67 ? "volume-mid" : "volume-high"

    function setVolume(v)  { if (sink && sink.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1, v)) } }
    function toggleMute()  { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted }
    function step(d)       { setVolume(volume + d) }
    function setMicVolume(v) { if (source && source.audio) source.audio.volume = Math.max(0, Math.min(1, v)) }
    function toggleMicMute() { if (source && source.audio) source.audio.muted = !source.audio.muted }

    // sinks / sources for the output-device picker
    readonly property var sinks:   Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    function setDefaultSink(node)   { Pipewire.preferredDefaultAudioSink = node }
    function setDefaultSource(node) { Pipewire.preferredDefaultAudioSource = node }
}
