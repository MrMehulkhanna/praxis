#!/usr/bin/env bash
# stage.sh DEST [AUR_REPO_DIR] — assemble everything Praxis adds on top of the
# Arch live system into DEST, laid out like the image's root file system:
#   iso/airootfs/ overlay, the desktop package list, /etc/skel (shell, Hyprland,
#   swaync, rofi, wallpapers), /opt/aios (tracked files only) and the bundled
#   [praxis] repository. build.sh stages into the archiso profile; the install
#   test stages into a scratch tree and points the installer at it.
set -euo pipefail
ISO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$ISO_DIR/.." && pwd)
DEST=${1:?destination}; AURREPO=${2:-}
SKEL=$DEST/etc/skel

cp -a "$ISO_DIR/airootfs/." "$DEST/"
# the desktop half of packages.x86_64 — the installer puts exactly this on targets
install -d "$DEST/usr/local/share/praxis"
sed '/^# @live-only/,$d' "$ISO_DIR/packages.x86_64" | grep -vE '^\s*(#|$)' >"$DEST/usr/local/share/praxis/desktop-packages.txt"

install -d "$SKEL/.config" "$SKEL/.local/share/wallpapers"
rsync -a --exclude settings.json --exclude eyecomfort.json "$REPO/desktop/quickshell/" "$SKEL/.config/quickshell/"
for d in hypr swaync rofi; do rsync -a "$REPO/desktop/$d/" "$SKEL/.config/$d/"; done
cp -r "$REPO"/desktop/wallpapers/. "$SKEL/.local/share/wallpapers/"      # stills + live/ videos
# the backend's user unit ships disabled; aios-setup enables it after the venv exists
install -Dm644 "$REPO/config/systemd/aios.service" "$SKEL/.config/systemd/user/aios.service"

install -d "$DEST/opt/aios"
git -C "$REPO" ls-files -z -- . ':!iso' ':!.github' ':!tests' ':!desktop/wallpapers' ':!docs/*.mp4' ':!docs/*.gif' ':!docs/screenshots' \
    | rsync -a --from0 --files-from=- "$REPO/" "$DEST/opt/aios/"
install -Dm644 "$REPO/requirements.txt" "$DEST/usr/local/share/aios/aios-requirements.txt"
if [ -n "$AURREPO" ]; then
    install -d "$DEST/opt/praxis-repo"
    cp -a "$AURREPO/." "$DEST/opt/praxis-repo/"
fi
