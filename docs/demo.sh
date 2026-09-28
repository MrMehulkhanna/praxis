#!/usr/bin/env bash
# ============================================================================
#  Record a ~2-minute scripted tour of Praxis — for LinkedIn, the README, demos.
#
#    bash docs/demo.sh [MONITOR]          default: the focused monitor
#
#  It takes over that monitor while it runs: windows on its current workspace
#  are parked on workspace 99 and put back afterwards, the wallpaper is
#  restored, and captions are desktop notifications. Plug in the charger first
#  (live wallpaper + local model). Output: ~/Videos/praxis-demo-<date>.mp4
# ============================================================================
set -uo pipefail
MON="${1:-$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')}"
OUT=~/Videos/praxis-demo-$(date +%Y%m%d-%H%M).mp4
TMP=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/praxis-demo.XXXX")
WP=~/.local/share/wallpapers/live
mkdir -p ~/Videos
say() { notify-send -a "Praxis" -t 3800 "$1" "${2:-}"; }
qs()  { quickshell ipc call "$@" >/dev/null 2>&1; }

# ── stage: park windows, pin the shell to the recorded monitor, warm the model ──
MONID=$(hyprctl monitors -j | jq -r --arg m "$MON" '.[] | select(.name == $m) | .id')
[ -n "$MONID" ] || { echo "no monitor named $MON" >&2; exit 1; }
ACTIVE_WS=$(hyprctl monitors -j | jq -r --arg m "$MON" '.[] | select(.name == $m) | .activeWorkspace.id')
PARKED=$(hyprctl clients -j | jq -r --argjson mon "$MONID" --argjson ws "$ACTIVE_WS" \
         '.[] | select(.monitor == $mon and .workspace.id == $ws) | .address')
WP_STATE=$(cat ~/.config/praxis/wallpaper.state 2>/dev/null || true)
for a in $PARKED; do hyprctl dispatch "hl.dsp.window.move({ workspace = 99, silent = true, window = \"address:$a\" })" >/dev/null; done
hyprctl eval "hl.window_rule({ name = 'praxis-demo', match = { class = '^praxis-demo$' }, monitor = '$MON', float = true, size = '1500 820', center = true })" >/dev/null
hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null
qs shell pin "$MON"; qs shell close; sleep 0.5
ai model auto >/dev/null 2>&1; ai ask "Reply with one word: ready" >/dev/null 2>&1 || true

cleanup() {
    touch "$TMP/stop"
    qs shell pin none; qs shell close; qs shell profile Normal
    for a in $PARKED; do hyprctl dispatch "hl.dsp.window.move({ workspace = $ACTIVE_WS, silent = true, window = \"address:$a\" })" >/dev/null; done
    if [ -n "$WP_STATE" ]; then
        printf '%s\n' "$WP_STATE" > ~/.config/praxis/wallpaper.state
        praxis-wallpaper restore --force >/dev/null 2>&1
    fi
}
trap cleanup EXIT

# ── frame capture (grim, as fast as the machine allows; fps measured after) ──
( i=0; start=$(date +%s.%N)
  while [ ! -f "$TMP/stop" ]; do
    grim -o "$MON" -t jpeg -q 88 "$TMP/f$(printf %05d $i).jpg" 2>/dev/null; i=$((i + 1))
  done
  python3 -c "import time; print($i, time.time() - $start)" > "$TMP/stats" ) &
CAP=$!
sleep 1

# ── the tour ─────────────────────────────────────────────────────────────────
say "Praxis" "An Arch-based Linux desktop with a local AI built in"; sleep 4
praxis-wallpaper live "$WP/horizon.mp4" >/dev/null 2>&1
say "Live wallpapers" "Rendered procedurally · one decoder for every screen · ~3 % CPU"; sleep 5
qs shell toggle widgets
say "Widgets · Super+B" "Clock, calendar, battery, system, weather, media"; sleep 5; qs shell close; sleep 1
qs shell toggle ws
say "12 desktops at a glance · Super+Tab"; sleep 4; qs shell close; sleep 1
qs shell search "fire"
say "Launcher · Super+Space" "Apps, files, calculator, shell — and ? asks the AI"; sleep 4; qs shell close; sleep 1
qs shell open cc
say "Control Center" "Real Wi-Fi, Bluetooth, audio · brightness 10–100 % (OLED-safe)"; sleep 5; qs shell close; sleep 1
say "Local AI · Super+I" "Runs on this laptop's GPU — nothing leaves the machine"
qs shell ask "In two short sentences: what is a local-first AI desktop good for?"; sleep 16; qs shell close; sleep 1
qs tasks open gpu
say "Task manager · Ctrl+Shift+Esc" "What is using the CPU and GPU right now — ✕ stops a task for real"; sleep 5
qs tasks open cpu; sleep 4; qs shell close; sleep 1
qs shell settings Wallpaper
say "Settings change the real system" "Still and live wallpapers · still image on battery"; sleep 5
qs shell settings Display; sleep 4
qs shell settings AI
say "Settings › AI" "Automatic model routing · cloud providers stay off until you add keys"; sleep 5; qs shell close; sleep 1
say "Terminal" "The ai CLI — same models, same memory"
kitty --class praxis-demo -o font_size=12 -o initial_window_width=1400 -o initial_window_height=760 bash -c '
  p(){ printf "\033[1;36m›\033[0m %s\n" "$*"; sleep 1.2; }
  p "ai status";  ai status;  sleep 2
  p "ai \"check my GPU and memory\"";  ai "check my GPU and memory"; sleep 4
  p "ai do \"set the volume to 40 percent\"";  ai do "set the volume to 40 percent"; sleep 3
' &
wait $! 2>/dev/null
say "Install it anywhere" "Boot the USB · the installer keeps Windows and installs only into free space"; sleep 4
say "Praxis" "github.com/MrMehulkhanna/praxis"; sleep 4

# ── encode ───────────────────────────────────────────────────────────────────
touch "$TMP/stop"; wait "$CAP" 2>/dev/null
read -r FRAMES SECS < "$TMP/stats"
FPS=$(python3 -c "print(max(1, round($FRAMES / $SECS)))")
echo "captured $FRAMES frames in ${SECS}s → ${FPS} fps"
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/f%05d.jpg" \
  -vf "scale=1920:-2:flags=lanczos,format=yuv420p" -c:v libx264 -preset medium -crf 20 -movflags +faststart "$OUT"
rm -rf "$TMP"
echo "video: $OUT ($(du -h "$OUT" | cut -f1))"
