#!/usr/bin/env bash
# ============================================================================
#  Write a Praxis ISO to a USB drive and verify the write.
#
#    iso/flash.sh                         newest ISO in the build dir, auto-detect USB
#    iso/flash.sh path/to/praxis.iso      a specific ISO
#    iso/flash.sh path/to/praxis.iso /dev/sdX
#
#  Safety: refuses anything that is not a USB disk, refuses the disk the
#  running system lives on, and asks you to type ERASE before writing.
# ============================================================================
set -euo pipefail
die() { printf '\n\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

BUILD=${PRAXIS_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/praxis-iso}
ISO=${1:-$(ls -t "$BUILD"/out/praxis-*.iso 2>/dev/null | head -1 || true)}
[ -n "$ISO" ] && [ -f "$ISO" ] || die "no ISO found — build one with iso/build.sh or pass its path"

rootdisk=/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" | head -1)
if [ -n "${2:-}" ]; then
    TARGET=$2
else
    mapfile -t cands < <(lsblk -dpno NAME,SIZE,TRAN,TYPE | awk -v rd="$rootdisk" '$3=="usb" && $4=="disk" && $2!="0B" && $1!=rd {print $1}')
    [ "${#cands[@]}" -eq 1 ] || die "found ${#cands[@]} USB disks (${cands[*]:-none}) — pass the device explicitly"
    TARGET=${cands[0]}
fi
[ -b "$TARGET" ] || die "$TARGET is not a block device"
[ "$(lsblk -dno TRAN "$TARGET")" = usb ] || die "$TARGET is not a USB disk — refusing"
[ "$TARGET" != "$rootdisk" ] || die "$TARGET holds the running system — refusing"

SIZE=$(stat -c %s "$ISO")
printf 'ISO     %s (%s)\n' "$ISO" "$(numfmt --to=iec "$SIZE")"
printf 'Target  %s — %s %s\n\n' "$TARGET" "$(lsblk -dno SIZE "$TARGET" | xargs)" "$(lsblk -dno MODEL "$TARGET" | xargs)"
printf '\033[1;31mEverything on %s will be erased.\033[0m\n' "$TARGET"
read -rp "Type ERASE to continue: " answer
[ "$answer" = ERASE ] || die "aborted — nothing written"

# Unmount anything the desktop auto-mounted from the stick.
for part in $(lsblk -lnpo NAME "$TARGET" | tail -n +2); do sudo umount "$part" 2>/dev/null || true; done

sudo dd if="$ISO" of="$TARGET" bs=4M conv=fsync oflag=direct status=progress
sync

printf '\nVerifying the write…\n'
want=$(sha256sum "$ISO" | cut -d' ' -f1)
have=$(sudo head -c "$SIZE" "$TARGET" | sha256sum | cut -d' ' -f1)
[ "$want" = "$have" ] || die "verification FAILED — the drive does not match the ISO (bad cable/port/stick?)"

printf '\033[1;32mDone — written and verified.\033[0m\n'
printf 'Boot it: plug into the target PC, open its boot menu (F12 / F9 / Esc / F8),\n'
printf 'choose the USB drive in UEFI mode, and click "Install Praxis Linux" in the dock.\n'
printf 'Secure Boot must be disabled in the firmware settings.\n'
