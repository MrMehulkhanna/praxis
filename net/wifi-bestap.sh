#!/usr/bin/env bash
# Pin to the fastest EACCESS BSSID by cycling and speed-testing each.
# Rechecks every RECHECK_MIN minutes and switches if a better AP appears.
# Caps download at CAP_MBIT via tc.

set -u
SSID="${SSID:-EACCESS}"
IFACE="${IFACE:-wlo1}"
CONN="${CONN:-EACCESS}"
CAP_MBIT="${CAP_MBIT:-190}"
RECHECK_MIN="${RECHECK_MIN:-20}"
TOP_N="${TOP_N:-5}"
TEST_SECS="${TEST_SECS:-8}"
LOG_DIR="${LOG_DIR:-$HOME/aios/net/logs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/bestap-$(date +%Y%m%d).log"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

apply_cap() {
  local rate="${1}mbit"
  sudo -n tc qdisc del dev "$IFACE" root 2>/dev/null || true
  sudo -n tc qdisc add dev "$IFACE" root tbf rate "$rate" burst 32kbit latency 50ms 2>>"$LOG" \
    && log "cap applied: $rate on $IFACE" \
    || log "cap FAILED (need passwordless sudo for tc)"
}

remove_cap_for_test() {
  sudo -n tc qdisc del dev "$IFACE" root 2>/dev/null || true
}

speed_mbit() {
  # returns integer Mbit/s (download); prefer ookla `speedtest`
  local out
  if command -v speedtest >/dev/null; then
    out=$(speedtest --accept-license --accept-gdpr -f json 2>/dev/null) || return 1
    # bandwidth is bytes/s
    python3 -c "import json,sys;d=json.loads('''$out''');print(int(d['download']['bandwidth']*8/1_000_000))" 2>/dev/null
  else
    out=$(speedtest-cli --simple --secure 2>/dev/null | awk '/Download/{print int($2)}')
    echo "${out:-0}"
  fi
}

pin_bssid() {
  local bssid="$1"
  nmcli con mod "$CONN" 802-11-wireless.bssid "$bssid" 2>>"$LOG"
  nmcli con down "$CONN" >/dev/null 2>&1
  nmcli con up "$CONN" >/dev/null 2>>"$LOG" || return 1
  sleep 6
  # wait for default route
  for _ in 1 2 3 4 5; do
    ip route get 1.1.1.1 >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

clear_pin() {
  nmcli con mod "$CONN" 802-11-wireless.bssid "" 2>>"$LOG"
}

top_bssids() {
  nmcli -t -f BSSID,SSID,SIGNAL,FREQ dev wifi list --rescan yes 2>/dev/null \
    | awk -F: -v s="$SSID" '
        {
          # BSSID has embedded colons escaped as \: — rebuild it
          bssid=$1":"$2":"$3":"$4":"$5":"$6
          gsub("\\\\","",bssid)
          ssid=$7; sig=$8; freq=$9
          if (ssid==s) print sig, bssid, freq
        }' \
    | sort -rn | head -n "$TOP_N" | awk '{print $2" "$3" "$1}'
}

test_all() {
  local best_bssid="" best_rate=0 line bssid freq sig rate
  log "=== scan start ==="
  local list; list=$(top_bssids)
  echo "$list" | tee -a "$LOG"
  remove_cap_for_test
  while read -r bssid freq sig; do
    [ -z "$bssid" ] && continue
    log "-> pin $bssid (sig=$sig freq=${freq}MHz)"
    if ! pin_bssid "$bssid"; then
      log "   assoc failed"; continue
    fi
    rate=$(speed_mbit); rate=${rate:-0}
    log "   $bssid = ${rate} Mbit/s"
    if [ "$rate" -gt "$best_rate" ]; then
      best_rate=$rate; best_bssid=$bssid
    fi
  done <<< "$list"
  if [ -n "$best_bssid" ]; then
    log "WINNER $best_bssid @ ${best_rate} Mbit/s"
    pin_bssid "$best_bssid" || log "final pin failed"
  else
    log "no winner; clearing pin"
    clear_pin; nmcli con up "$CONN" >/dev/null 2>&1
  fi
  apply_cap "$CAP_MBIT"
}

log "wifi-bestap starting (iface=$IFACE conn=$CONN cap=${CAP_MBIT}Mbit recheck=${RECHECK_MIN}m)"
while true; do
  test_all
  sleep "$((RECHECK_MIN*60))"
done
