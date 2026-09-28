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
SKEL=$AIROOT/etc/skel

# AUR packages bundled into a local [praxis] repo on the ISO. They are not
# installed into the live image; praxis-install installs them onto targets.
AUR_PKGS=(piper-tts-bin yay-bin mpvpaper)
GITHUB_ASSET_LIMIT=$((2 * 1024 * 1024 * 1024))

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

[ -f /etc/arch-release ] || die "the ISO must be built on Arch Linux (archiso)"
[ "$(id -u)" -ne 0 ] || die "run as a normal user — sudo is used where needed (makepkg refuses root)"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "$REPO is not a git checkout"
mkdir -p "$BUILD" "$OUT"

# ----------------------------------------------------------------------------
log "1/8  archiso"
command -v mkarchiso >/dev/null || sudo pacman -S --needed --noconfirm archiso

# ----------------------------------------------------------------------------
log "2/8  AUR packages → local [praxis] repository"
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
log "3/8  archiso profile (from releng)"
sudo rm -rf "$PROFILE"              # previous mkarchiso runs leave root-owned files
cp -r /usr/share/archiso/configs/releng "$PROFILE"
sed -i \
    -e 's/^iso_name=.*/iso_name="praxis"/' \
    -e "s/^iso_label=.*/iso_label=\"PRAXIS_$(date +%Y%m)\"/" \
    -e 's/^iso_publisher=.*/iso_publisher="Praxis Linux <https:\/\/github.com\/MrMehulkhanna\/praxis>"/' \
    -e 's/^iso_application=.*/iso_application="Praxis Linux live and installer"/' \
    "$PROFILE/profiledef.sh"

# ----------------------------------------------------------------------------
log "4/8  packages"
grep -vE '^\s*(#|$)' "$ISO_DIR/packages.x86_64" >> "$PROFILE/packages.x86_64"
sort -u -o "$PROFILE/packages.x86_64" "$PROFILE/packages.x86_64"
# Live image only: skip documentation and non-English translations (~0.5 GB).
# Installed systems are pacstrapped with the stock pacman.conf and get both.
sed -i '/^\[options\]/a NoExtract = usr/share/doc/* usr/share/gtk-doc/* usr/share/help/* usr/share/info/*\nNoExtract = usr/share/locale/* !usr/share/locale/en* !usr/share/locale/locale.alias' \
    "$PROFILE/pacman.conf"

# ----------------------------------------------------------------------------
log "5/8  overlay (iso/airootfs)"
cp -a "$ISO_DIR/airootfs/." "$AIROOT/"

# ----------------------------------------------------------------------------
log "6/8  desktop defaults → /etc/skel"
install -d "$SKEL/.config" "$SKEL/.local/share/wallpapers"
rsync -a --exclude settings.json --exclude eyecomfort.json \
    "$REPO/desktop/quickshell/" "$SKEL/.config/quickshell/"
for d in hypr swaync rofi; do rsync -a "$REPO/desktop/$d/" "$SKEL/.config/$d/"; done
cp "$REPO"/desktop/wallpapers/* "$SKEL/.local/share/wallpapers/"
# The backend's user unit ships disabled; aios-setup enables it after the venv exists.
install -Dm644 "$REPO/config/systemd/aios.service" "$SKEL/.config/systemd/user/aios.service"

# ----------------------------------------------------------------------------
log "7/8  AIOS backend → /opt/aios  (tracked files only)"
install -d "$AIROOT/opt/aios"
git -C "$REPO" ls-files -z -- . ':!iso' ':!.github' ':!tests' ':!desktop/wallpapers' ':!docs/*.mp4' ':!docs/*.gif' ':!docs/screenshots' \
    | rsync -a --from0 --files-from=- "$REPO/" "$AIROOT/opt/aios/"
install -Dm644 "$REPO/requirements.txt" "$AIROOT/usr/local/share/aios/aios-requirements.txt"
install -d "$AIROOT/opt/praxis-repo"
cp -a "$AURREPO/." "$AIROOT/opt/praxis-repo/"

# ----------------------------------------------------------------------------
log "8/8  permissions + mkarchiso"
# mkarchiso copies the overlay WITHOUT preserving modes; anything executable
# must be listed in file_permissions or it lands on the ISO as 0644.
{
    echo "file_permissions+=("
    (cd "$ISO_DIR/airootfs" && find . -type f -perm -u+x -printf '  ["/%P"]="0:0:755"\n')
    echo '  ["/etc/sudoers.d/praxis-live"]="0:0:440"'
    echo ")"
} >> "$PROFILE/profiledef.sh"
bash -n "$PROFILE/profiledef.sh" || die "generated profiledef.sh is invalid"

sudo rm -rf "$WORK"
sudo mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE"

ISO=$(ls -t "$OUT"/praxis-*.iso | head -1)
sudo chown "$(id -u):$(id -g)" "$ISO"
(cd "$OUT" && sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256")
SIZE=$(stat -c %s "$ISO")

printf '\n\033[1;32mISO ready\033[0m  %s  (%s)\n' "$ISO" "$(numfmt --to=iec "$SIZE")"
printf 'sha256     %s\n' "$(cut -d' ' -f1 "$ISO.sha256")"
[ "$SIZE" -le "$GITHUB_ASSET_LIMIT" ] || printf '\033[33mnote:\033[0m over 2 GiB — iso/publish.sh will split it for GitHub Releases\n'
printf '\nWrite to USB:  iso/flash.sh "%s"\n' "$ISO"
