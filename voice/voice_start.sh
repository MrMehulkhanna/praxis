#!/usr/bin/env bash
# scripts/voice_start.sh — begin push-to-talk recording.
# Called by VoiceButton.qml on press. Uses pw-record (native PipeWire,
# already on your system as your audio stack) rather than arecord/portaudio
# to avoid ALSA/PipeWire routing conflicts.
set -euo pipefail

WAV=/tmp/aios-voice.wav
PIDFILE=/tmp/aios-voice.pid

# clean up any stale recording from a previous crashed session
if [ -f "$PIDFILE" ]; then
  OLD=$(cat "$PIDFILE" 2>/dev/null || true)
  [ -n "$OLD" ] && kill "$OLD" 2>/dev/null || true
  rm -f "$PIDFILE"
fi
rm -f "$WAV"

# mono, 16kHz — exactly what whisper wants, no resampling step needed
pw-record --channels=1 --rate=16000 "$WAV" &
echo $! > "$PIDFILE"
