#!/usr/bin/env bash
# make-windows-disk.sh IMAGE [SIZE_GIB] — a disk image laid out like a UEFI
# Windows 11 install, for installer tests: EFI (with Windows Boot Manager),
# MSR, an NTFS "C:" with files in it, and a Windows recovery partition at the
# end. Prints the sha256 of the test data so a test can prove it survived.
# Needs root (loop devices), sgdisk, mkfs.fat, mkntfs (ntfsprogs).
set -euo pipefail
IMG=${1:?image}; SIZE=${2:-64}
rm -f "$IMG"; truncate -s "${SIZE}G" "$IMG"
sgdisk -o \
    -n 1:1M:+100M  -t 1:ef00 -c 1:"EFI system partition" \
    -n 2:0:+16M    -t 2:0c01 -c 2:"Microsoft reserved partition" \
    -n 3:0:-750M   -t 3:0700 -c 3:"Basic data partition" \
    -n 4:0:0       -t 4:2700 -c 4:"Basic data partition" "$IMG" >/dev/null
LOOP=$(losetup -fP --show "$IMG")
trap 'umount -q /tmp/.mkwin 2>/dev/null; losetup -d "$LOOP"' EXIT
udevadm settle
mkfs.fat -F32 -n SYSTEM "${LOOP}p1" >/dev/null
mkntfs -Q -L Windows "${LOOP}p3" >/dev/null 2>&1
mkntfs -Q -L Recovery "${LOOP}p4" >/dev/null 2>&1
mkdir -p /tmp/.mkwin
mount "${LOOP}p1" /tmp/.mkwin
mkdir -p /tmp/.mkwin/EFI/Microsoft/Boot /tmp/.mkwin/EFI/Boot
printf 'MZ fake Windows Boot Manager\n' >/tmp/.mkwin/EFI/Microsoft/Boot/bootmgfw.efi
printf 'regf fake boot configuration data\n' >/tmp/.mkwin/EFI/Microsoft/Boot/BCD   # os-prober needs it next to bootmgfw.efi
cp /tmp/.mkwin/EFI/Microsoft/Boot/bootmgfw.efi /tmp/.mkwin/EFI/Boot/bootx64.efi
umount /tmp/.mkwin
ntfs-3g "${LOOP}p3" /tmp/.mkwin
mkdir -p /tmp/.mkwin/Windows/System32 /tmp/.mkwin/Users/Alex/Documents
printf 'fake kernel\n' >/tmp/.mkwin/Windows/System32/ntoskrnl.exe
dd if=/dev/urandom of=/tmp/.mkwin/Users/Alex/Documents/photos.bin bs=1M count="${DATA_MIB:-400}" status=none
seq 1 200000 >/tmp/.mkwin/Users/Alex/Documents/notes.txt
(cd /tmp/.mkwin && find Users Windows -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
umount /tmp/.mkwin
