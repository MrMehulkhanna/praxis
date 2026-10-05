#!/usr/bin/env bash
# ============================================================================
#  Praxis ISO builder — a bootable live + installer image built from this repo.
#
#    iso/build.sh
#    PRAXIS_BUILD_DIR=/mnt/big/praxis iso/build.sh      # custom work location
#
#  Requirements: Arch Linux, internet, sudo (archiso and mkarchiso need root).
#  Everything that ships comes from the repository itself:
#    desktop/          Quickshell shell + Hyprland/swaync/rofi config, wallpapers
#    tracked files     the AIOS backend (git ls-files — nothing untracked leaks in)
#    iso/airootfs/     installer, praxis-* tools, services, branding
#    iso/packages.x86_64
#  Build products live outside the repo in $PRAXIS_BUILD_DIR.
# ============================================================================
set -euo pipefail

ISO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$ISO_DIR/.." && pwd)
BUILD=${PRAXIS_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/praxis-iso}
PROFILE=$BUILD/profile
WORK=$BUILD/work
OUT=${PRAXIS_OUT:-$BUILD/out}
AURREPO=$BUILD/aurrepo
AURBUILD=$BUILD/aurbuild
AIROOT=$PROFILE/airootfs

# AUR packages bundled into a local [praxis] repo on the ISO. They are not
# installed into the live image; praxis-install installs them onto targets.
AUR_PKGS=(piper-tts-bin yay-bin mpvpaper)
GITHUB_ASSET_LIMIT=$((2 * 1024 * 1024 * 1024))

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
# Delete a build tree as root without ever crossing into another filesystem:
# an interrupted mkarchiso can leave /proc, /sys or /dev bind-mounted inside it.
wipe() {
    local d=$1 m
    [ -e "$d" ] || return 0
    while read -r m; do sudo umount -l "$m" 2>/dev/null || true; done \
        < <(findmnt -rn -o TARGET | awk -v d="$d/" 'index($0, d) == 1' | sort -r)
    sudo rm -rf --one-file-system -- "$d"
}
die() { printf '\n\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

[ -f /etc/arch-release ] || die "the ISO must be built on Arch Linux (archiso)"
[ "$(id -u)" -ne 0 ] || die "run as a normal user — sudo is used where needed (makepkg refuses root)"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "$REPO is not a git checkout"
mkdir -p "$BUILD" "$OUT"

# ----------------------------------------------------------------------------
log "1/6  archiso"
command -v mkarchiso >/dev/null || sudo pacman -S --needed --noconfirm archiso

# ----------------------------------------------------------------------------
log "2/6  AUR packages → local [praxis] repository"
mkdir -p "$AURREPO"
collect_aur() {
    local pkg=$1 cached tmp
    # Reuse a previous build or the pacman cache when available (fast, offline).
    cached=$(ls -t "$AURREPO/$pkg"-[0-9]*-x86_64.pkg.tar.zst /var/cache/pacman/pkg/"$pkg"-[0-9]*-x86_64.pkg.tar.zst 2>/dev/null | head -1 || true)
    if [ -n "$cached" ]; then
        echo "   [cached] $(basename "$cached")"
        [ "$(dirname "$cached")" = "$AURREPO" ] || cp -n "$cached" "$AURREPO/"
        return
    fi
    echo "   [build]  $pkg"
    tmp="$AURBUILD/$pkg"
    rm -rf "$tmp"
    git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "$tmp"
    (cd "$tmp" && makepkg -sf --noconfirm --needed)
    find "$tmp" -maxdepth 1 -name "*-x86_64.pkg.tar.zst" ! -name "*-debug-*" -exec cp {} "$AURREPO/" \;
}
for p in "${AUR_PKGS[@]}"; do collect_aur "$p"; done
rm -f "$AURREPO"/*-debug-*.pkg.tar.zst "$AURREPO"/praxis.db* "$AURREPO"/praxis.files*
repo-add -q "$AURREPO/praxis.db.tar.gz" "$AURREPO"/*.pkg.tar.zst

# ----------------------------------------------------------------------------
log "3/6  archiso profile (from releng)"
wipe "$PROFILE"                     # previous mkarchiso runs leave root-owned files
cp -r /usr/share/archiso/configs/releng "$PROFILE"
sed -i \
    -e 's/^iso_name=.*/iso_name="praxis"/' \
    -e "s/^iso_label=.*/iso_label=\"PRAXIS_$(date +%Y%m)\"/" \
    -e 's/^iso_publisher=.*/iso_publisher="Praxis Linux <https:\/\/github.com\/MrMehulkhanna\/praxis>"/' \
    -e 's/^iso_application=.*/iso_application="Praxis Linux live and installer"/' \
    "$PROFILE/profiledef.sh"

# ----------------------------------------------------------------------------
log "4/6  packages + live services"
grep -vE '^\s*(#|$)' "$ISO_DIR/packages.x86_64" >> "$PROFILE/packages.x86_64"
# releng is a rescue disc; this image is for trying the desktop and installing
# it. Drop the rescue / VPN / remote-admin extras (~0.3 GB) and their units.
RELENG_DROP=(archinstall bcachefs-tools bind clonezilla cloud-init darkhttpd ddrescue dmraid dnsmasq
             edk2-shell fatresize fsarchiver gpart gpm grml-zsh-config irssi jfsutils ldns lftp linux-atm
             lsscsi lynx mc mmc-utils modemmanager nbd ndisc6 nfs-utils nilfs-utils nmap open-iscsi
             open-vm-tools openconnect openpgp-card-tools openvpn partclone partimage pcsclite ppp
             pptpclient refind rxvt-unicode-terminfo screen sdparm sequoia-sq sg3_utils tcpdump testdisk
             tmux tpm2-tools udftools vim vpnc wvdial xl2tpd)
grep -vxF -f <(printf '%s\n' "${RELENG_DROP[@]}") "$PROFILE/packages.x86_64" | sort -u > "$PROFILE/packages.new"
mv "$PROFILE/packages.new" "$PROFILE/packages.x86_64"
UNITS=$AIROOT/etc/systemd/system
rm -rf "$UNITS/cloud-init.target.wants"
rm -f "$UNITS/dbus-org.freedesktop.ModemManager1.service" "$UNITS/multi-user.target.wants/ModemManager.service" \
      "$UNITS/multi-user.target.wants/vmtoolsd.service" "$UNITS/multi-user.target.wants/vmware-vmblock-fuse.service" \
      "$UNITS/sockets.target.wants/pcscd.socket"
# NetworkManager owns the network — the shell's Wi-Fi panel and the installer's
# nmtui both talk to it. releng's iwd + systemd-networkd would fight it for the
# Wi-Fi card, so they go; Bluetooth comes on for the shell's Bluetooth panel.
rm -f "$UNITS/multi-user.target.wants/iwd.service" "$UNITS/multi-user.target.wants/systemd-networkd.service" \
      "$UNITS/sockets.target.wants/systemd-networkd.socket" "$UNITS/dbus-org.freedesktop.network1.service" \
      "$UNITS/network-online.target.wants/systemd-networkd-wait-online.service"
rm -rf "$AIROOT/etc/systemd/network"
# systemd's own presets re-enable networkd during pacstrap, so mask it and its
# sockets (its wait-online would otherwise stall boot waiting for links it can't
# manage). Also mask systemd-loop@: a udev rule tries to loop-attach every ISO9660
# disc, fails on the boot medium, and leaves the live system "degraded". archiso
# mounts its image in the initramfs and doesn't need it.
for u in systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service \
         systemd-networkd-varlink.socket systemd-networkd-varlink-metrics.socket \
         systemd-networkd-resolve-hook.socket systemd-loop@.service; do
    ln -sf /dev/null "$UNITS/$u"
done
install -d "$UNITS/multi-user.target.wants" "$UNITS/bluetooth.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$UNITS/multi-user.target.wants/NetworkManager.service"
ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service "$UNITS/dbus-org.freedesktop.nm-dispatcher.service"
ln -sf /usr/lib/systemd/system/bluetooth.service "$UNITS/bluetooth.target.wants/bluetooth.service"
ln -sf /usr/lib/systemd/system/bluetooth.service "$UNITS/dbus-org.bluez.service"
# The live account has a published password and passwordless sudo: never
# accept it over the network. (iso/airootfs also blocks password SSH for it.)
rm -f "$UNITS/multi-user.target.wants/sshd.service"
# The live session gets live wallpapers too: mpvpaper from the bundled [praxis]
# repository. Build-time only — mkarchiso does not copy this pacman.conf into the
# image; praxis-install registers /opt/praxis-repo on targets itself.
printf '\n[praxis]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$AURREPO" >> "$PROFILE/pacman.conf"
echo mpvpaper >> "$PROFILE/packages.x86_64"
# Live image only: skip documentation and non-English translations (~0.5 GB).
# Installed systems are pacstrapped with the stock pacman.conf and get both.
sed -i '/^\[options\]/a NoExtract = usr/share/doc/* usr/share/gtk-doc/* usr/share/help/* usr/share/info/*\nNoExtract = usr/share/locale/* !usr/share/locale/en* !usr/share/locale/locale.alias' \
    "$PROFILE/pacman.conf"

# ----------------------------------------------------------------------------
log "5/6  overlay, desktop defaults, AIOS backend (stage.sh)"
"$ISO_DIR/stage.sh" "$AIROOT" "$AURREPO"

# ----------------------------------------------------------------------------
log "6/6  permissions + mkarchiso"
# mkarchiso copies the overlay WITHOUT preserving modes; anything executable
# must be listed in file_permissions or it lands on the ISO as 0644.
{
    echo "file_permissions+=("
    (cd "$ISO_DIR/airootfs" && find . -type f -perm -u+x -printf '  ["/%P"]="0:0:755"\n')
    echo '  ["/etc/sudoers.d/praxis-live"]="0:0:440"'
    echo ")"
} >> "$PROFILE/profiledef.sh"
bash -n "$PROFILE/profiledef.sh" || die "generated profiledef.sh is invalid"

wipe "$WORK"
sudo mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE"

ISO=$(ls -t "$OUT"/praxis-*.iso | head -1)
sudo chown "$(id -u):$(id -g)" "$ISO"
(cd "$OUT" && sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256")
SIZE=$(stat -c %s "$ISO")

printf '\n\033[1;32mISO ready\033[0m  %s  (%s)\n' "$ISO" "$(numfmt --to=iec "$SIZE")"
printf 'sha256     %s\n' "$(cut -d' ' -f1 "$ISO.sha256")"
[ "$SIZE" -le "$GITHUB_ASSET_LIMIT" ] || printf '\033[33mnote:\033[0m over 2 GiB — iso/publish.sh will split it for GitHub Releases\n'
printf '\nWrite to USB:  iso/flash.sh "%s"\n' "$ISO"
