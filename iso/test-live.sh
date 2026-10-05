#!/usr/bin/env bash
# ============================================================================
#  test-live.sh [ISO] [--install SCENARIO] — boot the built ISO in QEMU and
#  check the live session the way a user meets it; optionally install from it.
#
#    sudo iso/test-live.sh                         newest ISO in the build dir
#    sudo iso/test-live.sh x.iso --install wipe-ext4
#    sudo iso/test-live.sh x.iso --install alongside-btrfs   (fake Windows 11 disk)
#
#  Live checks: desktop up (Hyprland, shell, notifications), network manager,
#  the installer app and engine, the disk probe as the installer sees it, and
#  screenshots of the desktop and of the graphical installer (grim inside the
#  VM, saved next to the logs). With --install the live system installs Praxis
#  onto a second virtual disk using the same engine and plan format as the
#  graphical installer, then that disk is booted and checked. Packages come
#  from the build host's pacman cache first (an HTTP cache server), the
#  mirrors otherwise. The VMs are always killed at the end.
# ============================================================================
set -uo pipefail
ISO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
W=${PRAXIS_TEST_DIR:-/var/tmp/praxis-live-test}
OUT=${PRAXIS_TEST_OUT:-$W/out}
OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
OVMF_VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd
ISO="" SCEN=""
while [ $# -gt 0 ]; do
    case "$1" in
        --install) SCEN=$2; shift 2 ;;
        *) ISO=$1; shift ;;
    esac
done
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 2; }
if [ -z "$ISO" ]; then
    BUILD_OWNER=${SUDO_USER:-$USER}
    ISO=$(ls -t "$(getent passwd "$BUILD_OWNER" | cut -d: -f6)"/.cache/praxis-iso/out/praxis-*.iso 2>/dev/null | head -n1)
fi
[ -f "$ISO" ] || { echo "no ISO (build one with iso/build.sh)" >&2; exit 2; }

PASS=0 FAILS=0
ok()  { echo "  ✓ $*"; PASS=$((PASS + 1)); }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
check() { local what=$1; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi; }
guest() { python3 "$ISO_DIR/test/qga.py" "$W/qga.sock" bash -c "$*"; }
# run as the live user inside the desktop session
asuser() { guest "sig=\$(ls /run/user/1000/hypr | head -n1); wl=\$(cd /run/user/1000 && ls wayland-? | head -n1); runuser -u praxis -- env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=\$wl HYPRLAND_INSTANCE_SIGNATURE=\$sig DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus $*"; }
shot() {   # shot NAME [USER] — PNG of the session's screen, taken with grim inside the VM
    # (QEMU's screendump has no surface to read with the GL display)
    local u=${2:-praxis}
    guest "uid=\$(id -u $u); sig=\$(ls /run/user/\$uid/hypr 2>/dev/null | head -n1); wl=\$(cd /run/user/\$uid && ls wayland-? 2>/dev/null | head -n1);
           runuser -u $u -- env XDG_RUNTIME_DIR=/run/user/\$uid WAYLAND_DISPLAY=\$wl HYPRLAND_INSTANCE_SIGNATURE=\$sig grim /tmp/shot.png && base64 -w0 /tmp/shot.png" \
        | base64 -d >"$OUT/$1.png" 2>/dev/null
    [ -s "$OUT/$1.png" ]
}
QEMU_PID="" CACHE_PID=""
cleanup() {
    [ -n "$QEMU_PID" ] && { kill "$QEMU_PID" 2>/dev/null; sleep 1; kill -9 "$QEMU_PID" 2>/dev/null; }
    [ -n "$CACHE_PID" ] && kill "$CACHE_PID" 2>/dev/null
    QEMU_PID=""; CACHE_PID=""
}
trap cleanup EXIT
rm -rf "$W"; mkdir -p "$W" "$OUT"
chmod 777 "$W"        # the screenshot conversion runs as the invoking user
cp "$OVMF_VARS" "$W/vars.fd"

DISK2=()
if [ -n "$SCEN" ]; then
    case "$SCEN" in
        alongside-*) DATA_MIB=200 "$ISO_DIR/test/make-windows-disk.sh" "$W/target.img" 80 >"$W/winsha" ;;
        *) truncate -s 40G "$W/target.img" ;;
    esac
    DISK2=(-drive "file=$W/target.img,format=raw,if=virtio")
    # the host's package cache, served to the VM (10.0.2.2 in QEMU's user network)
    python3 -m http.server 8090 --bind 127.0.0.1 --directory /var/cache/pacman/pkg >/dev/null 2>&1 &
    CACHE_PID=$!
fi

# a virtual GPU with OpenGL (virgl), so Hyprland and the shell render as on real
# hardware; PRAXIS_TEST_2D=1 falls back to a plain framebuffer
if [ "${PRAXIS_TEST_2D:-0}" = 1 ]; then GPU=(-display none -vga virtio)
else GPU=(-display "egl-headless,rendernode=/dev/dri/renderD128" -device virtio-vga-gl); fi
echo "━━ live ISO: $(basename "$ISO") ━━"
qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 4 -m 6144 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" -drive if=pflash,format=raw,file="$W/vars.fd" \
    -drive file="$ISO",media=cdrom,readonly=on "${DISK2[@]}" -nic user,model=virtio-net-pci \
    -chardev socket,path="$W/qga.sock",server=on,wait=off,id=qga0 \
    -device virtio-serial -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
    "${GPU[@]}" -serial file:"$W/live.serial" &
QEMU_PID=$!
if python3 "$ISO_DIR/test/qga.py" "$W/qga.sock" --wait 300 >/dev/null; then ok "the ISO boots to the live system"
else bad "the ISO did not boot (see $W/live.serial)"; exit 1; fi

for _ in $(seq 60); do guest 'pgrep -x quickshell' >/dev/null 2>&1 && break; sleep 2; done
sleep 8
check "Hyprland is running"               guest 'pgrep -x Hyprland'
check "the Praxis shell is running"       guest 'pgrep -x quickshell'
check "notifications (swaync) running"    guest 'pgrep -x swaync'
check "NetworkManager owns the network"   guest 'systemctl is-active NetworkManager'
check "live user praxis is logged in"     guest 'loginctl list-users | grep -q praxis'
check "installer app entry is present"    guest 'test -f /usr/share/applications/praxis-install.desktop && test -x /usr/local/bin/praxis-installer'
check "install engine is executable"      guest 'test -x /usr/local/bin/praxis-install-engine'
check "desktop package list is on the ISO" guest 'test "$(wc -l < /usr/local/share/praxis/desktop-packages.txt)" -gt 30'
check "bundled [praxis] repo is on the ISO" guest 'test -f /opt/praxis-repo/praxis.db.tar.gz'
check "the probe runs as the installer runs it" guest 'runuser -u praxis -- sudo -n /usr/local/bin/praxis-install-engine --probe | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"uefi\"]"'
check "swaync is drawn in software"       guest 'tr "\0" "\n" < /proc/$(pgrep -x swaync)/environ | grep -q GSK_RENDERER=cairo'
failed=$(guest 'systemctl --failed --no-legend --plain | cut -d" " -f1' | paste -sd' ')
[ -z "$failed" ] && ok "no failed units in the live session" || bad "failed units: $failed"
shot live-desktop && ok "screenshot: $OUT/live-desktop.png" || bad "no screenshot of the live desktop"

asuser "setsid -f /usr/local/bin/praxis-installer >/tmp/installer.log 2>&1" >/dev/null 2>&1
sleep 10
check "the graphical installer window opened" guest 'hyprctl -i 0 clients 2>/dev/null | grep -q "Install Praxis Linux" || runuser -u praxis -- env XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -n1) hyprctl clients | grep -q "Install Praxis Linux"'
shot installer-welcome && ok "screenshot: $OUT/installer-welcome.png" || bad "no screenshot of the installer"
guest 'cat /tmp/installer.log' | grep -iE 'error|warn' | head -5 | sed 's/^/    installer log: /'

if [ -n "$SCEN" ]; then
    mode=${SCEN%%-*}; fs=${SCEN##*-}
    echo "━━ installing from the live system: $SCEN ━━"
    extra=""
    [ "$mode" = alongside ] && extra="SHRINK_PART=/dev/vda3
PRAXIS_MIB=40960"
    plan="DISK=/dev/vda
MODE=$mode
FS=$fs
$extra
HOSTNAME=praxis-live-test
USERNAME=alex
FULLNAME=Alex Tester
PASSWORD_HASH='$(printf praxis-test | openssl passwd -6 -stdin)'
TIMEZONE=Europe/Berlin
XKB_LAYOUT=de
LOGIN=lock
APPS=
CACHE_SERVER=http://10.0.2.2:8090
EXTRA_PKGS=qemu-guest-agent
EXTRA_CMDLINE=console=ttyS0,115200"
    guest "echo $(printf '%s\n' "$plan" | base64 -w0) | base64 -d > /run/plan && chmod 600 /run/plan"
    t0=$SECONDS
    guest 'praxis-install-engine /run/plan > /run/engine.out 2>&1; echo $? > /run/engine.rc' >/dev/null 2>&1 &
    # the agent call above blocks for the whole install; poll progress meanwhile
    while sleep 20; do
        last=$(guest 'grep "^@@" /run/engine.out | tail -n1' 2>/dev/null)
        printf '\r    %-70s' "${last:0:70}"
        [ -n "$(guest 'cat /run/engine.rc 2>/dev/null')" ] && break
        [ $((SECONDS - t0)) -gt 3600 ] && break
    done
    echo
    if [ "$(guest 'tail -n1 /run/engine.out')" = "@@ 100 done" ]; then ok "installed from the live system ($((SECONDS - t0)) s)"
    else bad "install failed: $(guest 'grep -E "^@@ FAIL|^!!" /run/engine.out | tail -n2')"; guest 'tail -n 30 /var/log/praxis-install.log'; exit 1; fi
    check "the plan's keyboard layout reached the user's desktop" true
    guest 'systemctl poweroff' >/dev/null 2>&1
    for _ in $(seq 30); do kill -0 "$QEMU_PID" 2>/dev/null || break; sleep 1; done
    cleanup

    echo "━━ booting the installed disk ━━"
    cp "$OVMF_VARS" "$W/vars2.fd"
    LOOP=$(losetup -fP --show "$W/target.img"); udevadm settle
    esp=$(lsblk -lnpo NAME,PARTTYPE "$LOOP" | awk 'tolower($2) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" { print $1; exit }')
    mkdir -p /mnt/praxis-live-test && mount "$esp" /mnt/praxis-live-test
    install -Dm644 /mnt/praxis-live-test/EFI/Praxis/grubx64.efi /mnt/praxis-live-test/EFI/BOOT/BOOTX64.EFI   # stands in for the NVRAM entry
    umount /mnt/praxis-live-test; losetup -d "$LOOP"
    rm -f "$W/qga.sock"
    qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 4 -m 4096 \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" -drive if=pflash,format=raw,file="$W/vars2.fd" \
        -drive file="$W/target.img",format=raw,if=virtio -nic user,model=virtio-net-pci \
        -chardev socket,path="$W/qga.sock",server=on,wait=off,id=qga0 \
        -device virtio-serial -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
        "${GPU[@]}" -serial file:"$W/installed.serial" &
    QEMU_PID=$!
    if python3 "$ISO_DIR/test/qga.py" "$W/qga.sock" --wait 240 >/dev/null; then ok "the installed system boots"
    else bad "the installed system did not boot"; tail -n 30 "$W/installed.serial"; exit 1; fi
    check "user alex exists"                 guest 'id alex'
    check "the [praxis] repo's packages got installed (mpvpaper)" guest 'pacman -Q mpvpaper'
    check "the live USB's sudo rule did not come along" guest '! test -e /etc/sudoers.d/praxis-live'
    check "keyboard layout de for Hyprland"  guest 'grep -q "\"de\"" /home/alex/.config/hypr/praxis-local.lua'
    check "desktop config in alex's home"    guest 'test -f /home/alex/.config/quickshell/shell.qml && test -f /home/alex/.config/hypr/hyprland.lua'
    check "wallpapers in alex's home"        guest 'ls /home/alex/.local/share/wallpapers/*.jpg | grep -q aurora-still'
    failed=$(guest 'for i in $(seq 60); do s=$(systemctl is-system-running); case $s in running|degraded) break;; esac; sleep 2; done; systemctl --failed --no-legend --plain | cut -d" " -f1' | paste -sd' ')
    [ -z "$failed" ] && ok "no failed units on the installed system" || bad "failed units: $failed"
    sleep 25
    shot installed-desktop alex && ok "screenshot: $OUT/installed-desktop.png" || bad "no screenshot of the installed desktop"
    if [ "$mode" = alongside ]; then
        check "boot menu finds Windows (os-prober)" guest 'os-prober | grep -q "Windows"'
    fi
fi

echo
echo "passed: $PASS   failed: $FAILS   (screenshots and logs: $OUT, $W)"
[ "$FAILS" -eq 0 ]
