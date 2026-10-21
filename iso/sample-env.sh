#!/usr/bin/env bash
# ============================================================================
#  sample-env.sh — Isolated sample environment to examine and verify the Praxis
#  ISO drivers, kernel modules, sound firmware, display scripts, and bootloader
#  without modifying or touching the host PC.
#
#    sudo iso/sample-env.sh [path/to/praxis.iso]
# ============================================================================
set -euo pipefail

ISO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$ISO_DIR/.." && pwd)
BUILD=${PRAXIS_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/praxis-iso}
ISO=${1:-$(ls -t "$BUILD"/out/praxis-*.iso 2>/dev/null | head -1 || true)}

ENV_DIR=${SAMPLE_ENV_DIR:-/var/tmp/praxis-sample-env}
MNT_ISO="$ENV_DIR/iso"
MNT_SFS="$ENV_DIR/squashfs"
mkdir -p "$ENV_DIR" "$MNT_ISO" "$MNT_SFS"

cleanup() {
    sudo umount -l "$MNT_SFS" 2>/dev/null || true
    sudo umount -l "$MNT_ISO" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================================================"
echo "  Praxis ISO Sample Environment — Hardware & Software Verification"
echo "========================================================================"

[ -n "$ISO" ] && [ -f "$ISO" ] || { echo "!! No ISO found at $ISO"; exit 1; }
echo "Target ISO: $ISO ($(stat -c %s "$ISO" | numfmt --to=iec))"
echo "Sample Environment Path: $ENV_DIR"

echo -e "\n[1/5] Mounting ISO read-only in sample environment..."
sudo mount -o loop,ro "$ISO" "$MNT_ISO"

SFS="$MNT_ISO/arch/x86_64/airootfs.sfs"
if [ -f "$SFS" ]; then
    echo "Found root filesystem: $SFS"
    sudo mount -o loop,ro "$SFS" "$MNT_SFS"
    ROOT="$MNT_SFS"
else
    echo "Using direct ISO root"
    ROOT="$MNT_ISO"
fi

PASS=0
FAIL=0
check() {
    local desc=$1; shift
    if eval "$@"; then
        printf "  ✓ %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  ✗ %s\n" "$desc"
        FAIL=$((FAIL + 1))
    fi
}

echo -e "\n[2/5] Examining Boot, Initramfs & Storage Drivers (VMD / NVMe / Emergency)..."
check "GRUB bootloader present" "[ -f '$MNT_ISO/boot/grub/grub.cfg' ] || [ -f '$ROOT/boot/grub/grub.cfg' ] || [ -d '$MNT_ISO/EFI' ]"
check "Kernel vmlinuz present" "[ -f '$MNT_ISO/arch/boot/x86_64/vmlinuz-linux' ] || [ -f '$ROOT/boot/vmlinuz-linux' ]"
check "Initramfs image present" "[ -f '$MNT_ISO/arch/boot/x86_64/initramfs-linux.img' ] || [ -f '$ROOT/boot/initramfs-linux.img' ]"
check "Emergency service SULOGIN force override exists" "[ -f '$ROOT/etc/systemd/system/emergency.service.d/override.conf' ] && grep -q 'SYSTEMD_SULOGIN_FORCE=1' '$ROOT/etc/systemd/system/emergency.service.d/override.conf'"
check "Rescue service SULOGIN force override exists" "[ -f '$ROOT/etc/systemd/system/rescue.service.d/override.conf' ] && grep -q 'SYSTEMD_SULOGIN_FORCE=1' '$ROOT/etc/systemd/system/rescue.service.d/override.conf'"
check "Installer engine configures VMD & NVMe drivers" "grep -q 'MODULES=(vmd nvme ahci uas usb_storage btrfs ext4)' '$ROOT/usr/local/bin/praxis-install-engine'"
check "Installer engine injects SYSTEMD_SULOGIN_FORCE into GRUB cmdline" "grep -q 'SYSTEMD_SULOGIN_FORCE=1' '$ROOT/usr/local/bin/praxis-install-engine'"

echo -e "\n[3/5] Examining Audio Subsystem & Modern PC Drivers (SOF / ALSA UCM / Microphones)..."
check "Sound Open Firmware (SOF) present" "[ -d '$ROOT/usr/lib/firmware/intel/sof' ] || [ -d '$ROOT/usr/lib/firmware/intel/sof-ace' ] || [ -f '$ROOT/usr/lib/firmware/intel/sof/sof-tgl.ri' ]"
check "ALSA Use Case Manager (UCM2) profiles present" "[ -d '$ROOT/usr/share/alsa/ucm2' ] && [ -f '$ROOT/usr/share/alsa/ucm2/ucm.conf' ]"
check "PipeWire audio daemon present" "[ -f '$ROOT/usr/bin/pipewire' ] && [ -f '$ROOT/usr/bin/pipewire-pulse' ]"
check "WirePlumber session manager present" "[ -f '$ROOT/usr/bin/wireplumber' ]"
check "WirePlumber speaker priority rule present" "[ -f '$ROOT/etc/wireplumber/wireplumber.conf.d/50-speaker-priority.conf' ]"
check "WirePlumber internal microphone / dmic priority configured" "grep -q 'alsa_input.*dmic' '$ROOT/etc/wireplumber/wireplumber.conf.d/50-speaker-priority.conf'"
check "WirePlumber speaker preferred over HDMI" "grep -q 'node.name.*alsa_output.*hdmi' '$ROOT/etc/wireplumber/wireplumber.conf.d/50-speaker-priority.conf' && grep -q 'priority.session = 600' '$ROOT/etc/wireplumber/wireplumber.conf.d/50-speaker-priority.conf'"
check "praxis-audio tool included" "[ -x '$ROOT/usr/local/bin/praxis-audio' ] || [ -f '$ISO_DIR/airootfs/usr/local/bin/praxis-audio' ]"

echo -e "\n[4/5] Examining Display, Projection & Wayland/Hyprland Subsystem..."
check "Hyprland compositor binary present" "[ -f '$ROOT/usr/bin/Hyprland' ]"
check "Quickshell desktop shell present" "[ -f '$ROOT/usr/bin/quickshell' ]"
check "praxis-display utility present and executable" "[ -x '$ROOT/usr/local/bin/praxis-display' ]"
check "praxis-display supports project mode (pc, second, duplicate, extend)" "grep -q 'project)' '$ROOT/usr/local/bin/praxis-display' && grep -q 'duplicate)' '$ROOT/usr/local/bin/praxis-display'"
check "praxis-display automatically resolves Hyprland socket" "grep -q 'HYPRLAND_INSTANCE_SIGNATURE' '$ROOT/usr/local/bin/praxis-display'"
check "praxis-display clears mirror flag on projection" "grep -q 'mirror' '$ROOT/usr/local/bin/praxis-display'"

echo -e "\n[5/5] Examining Power, Sleep & User Lockout Security..."
check "hypridle daemon present" "[ -f '$ROOT/usr/bin/hypridle' ]"
check "hyprlock locker present" "[ -f '$ROOT/usr/bin/hyprlock' ]"
check "hypridle configuration locks before sleep and listens for idle" "([ -f '$ROOT/etc/skel/.config/hypr/hypridle.conf' ] || [ -f '$ROOT/etc/hypr/hypridle.conf' ] || [ -f '$REPO/desktop/hypr/hypridle.conf' ])"
check "Lid switch suspend configured in logind" "[ -f '$ROOT/etc/systemd/logind.conf.d/10-praxis.conf' ] && grep -q 'HandleLidSwitch=suspend' '$ROOT/etc/systemd/logind.conf.d/10-praxis.conf'"
check "Desktop package manifest includes audio & driver packages" "grep -q 'sof-firmware' '$ROOT/usr/local/share/praxis/desktop-packages.txt' && grep -q 'alsa-ucm-conf' '$ROOT/usr/local/share/praxis/desktop-packages.txt'"

echo -e "\n========================================================================"
echo "  Sample Environment Verification Summary: $PASS Passed, $FAIL Failed"
echo "========================================================================"

if [ "$FAIL" -eq 0 ]; then
    echo "All ISO drivers, audio firmware, bootloader configurations, and display tools verified successfully!"
    exit 0
else
    echo "!! Verification had $FAIL failures. Examine the items above."
    exit 1
fi
