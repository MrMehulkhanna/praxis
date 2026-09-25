#!/usr/bin/env bash
# Records a scripted tour of the desktop + local AI into ~/Videos/aios-demo-<date>.mp4
# Uses grim frame capture (no wf-recorder needed) and drives the shell via IPC.
set -uo pipefail
MON="${1:-HDMI-A-1}"
OUT=~/Videos/aios-demo-$(date +%Y%m%d-%H%M).mp4
TMP=$(mktemp -d /tmp/aios-demo.XXXX)
mkdir -p ~/Videos
say() { notify-send -a "AIOS demo" -t 3500 "$1" "${2:-}"; }
qs() { quickshell ipc call shell "$@" >/dev/null 2>&1; }

# park whatever is on the recorded monitor on a hidden workspace (restored at the end),
# pin the shell's overlays to that monitor, warm the model
MONID=$(hyprctl monitors -j | python3 -c "import json,sys; print([m for m in json.load(sys.stdin) if m['name']=='$MON'][0]['id'])")
ACTIVE_WS=$(hyprctl monitors -j | python3 -c "import json,sys; print([m for m in json.load(sys.stdin) if m['name']=='$MON'][0]['activeWorkspace']['id'])")
PARKED=$(hyprctl clients -j | python3 -c "import json,sys; print(' '.join(c['address'] for c in json.load(sys.stdin) if c['monitor']==$MONID and c['workspace']['id']==$ACTIVE_WS))")
for a in $PARKED; do hyprctl dispatch "hl.dsp.window.move({ workspace = 99, silent = true, window = \"address:$a\" })" >/dev/null; done
hyprctl eval "hl.window_rule({ name = 'aios-demo', match = { class = '^aios-demo$' }, monitor = '$MON', float = true, size = '1500 820', center = true })" >/dev/null
hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null
qs pin "$MON"; qs close; sleep 0.5
ai model auto >/dev/null 2>&1; ai ask "Reply with one word: ready" >/dev/null 2>&1 || true
cleanup() { qs pin none; qs close; for a in $PARKED; do hyprctl dispatch "hl.dsp.window.move({ workspace = $ACTIVE_WS, silent = true, window = \"address:$a\" })" >/dev/null; done; }
trap cleanup EXIT

# ── frame capture loop ────────────────────────────────────────────────
( i=0; start=$(date +%s.%N)
  while [ ! -f "$TMP/stop" ]; do
    grim -o "$MON" -t jpeg -q 88 "$TMP/f$(printf %05d $i).jpg" 2>/dev/null; i=$((i+1))
  done
  python3 -c "import time,sys; print($i, time.time() - $start)" > "$TMP/stats" ) &
CAP=$!
sleep 1

say "AIOS" "Local-first AI desktop · Arch + Hyprland + Quickshell"; sleep 4
say "Launcher" "Super+A · apps, > control PC, ? ask AI"; qs search "ter"; sleep 4; qs close; sleep 1
say "Control Center" "Real Wi-Fi, Bluetooth, audio, brightness, power — nothing faked"; qs open cc; sleep 5; qs close; sleep 1
say "AI panel" "Runs 100% locally · one model selection everywhere"; qs ask "In two short sentences: what is a local-first AI desktop good for?"; sleep 16
say "Activity" "Every step visible: classify → route → generate → result"; qs open activity; sleep 6; qs close; sleep 1
say "Profiles" "Development profile: accent, stats in the bar, performance power mode"; qs profile Development; sleep 1; qs settings Profiles; sleep 4
say "Settings → AI" "Auto routing, cloud providers (off until you add keys), ₹0 budget"; qs settings AI; sleep 5
say "Settings → Power" "ASUS hardware: fan, keyboard backlight, charge limit"; qs settings Power; sleep 5; qs close; sleep 1
qs profile Normal
say "Terminal" "the ai CLI — same brain, same memory"
kitty --class aios-demo -o font_size=12 -o initial_window_width=1400 -o initial_window_height=760 bash -c '
  p(){ printf "\033[1;36m›\033[0m %s\n" "$*"; sleep 1.2; }
  p "ai status";  ai status;  sleep 2
  p "ai models";  ai models;  sleep 4
  p "ai \"check my GPU and memory\"";  ai "check my GPU and memory"; sleep 4
  p "ai do \"set the volume to 40 percent\"";  ai do "set the volume to 40 percent"; sleep 3
  p "ai hardware"; ai hardware; sleep 5
' &
KITTY=$!
wait $KITTY 2>/dev/null
say "Voice" "Hold the mic in the bar: \"switch to the coding model\", \"check GPU usage\", \"open browser\""; sleep 4
say "AIOS" "Everything you just saw ran on this laptop. github: your repo here"; sleep 4

touch "$TMP/stop"; wait $CAP 2>/dev/null
read -r FRAMES SECS < "$TMP/stats"
FPS=$(python3 -c "print(max(1, round($FRAMES / $SECS)))")
echo "captured $FRAMES frames in ${SECS}s → ${FPS} fps"
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/f%05d.jpg" \
  -vf "scale=1920:-2:flags=lanczos,format=yuv420p" -c:v libx264 -preset medium -crf 20 -movflags +faststart "$OUT"
rm -rf "$TMP"
echo "video: $OUT ($(du -h "$OUT" | cut -f1))"
