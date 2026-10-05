# shellcheck shell=bash
# Shared by praxis-install and praxis-install-partition.

# praxis_packages — what pacstrap installs on a Praxis system, one per line:
# the base system, the Praxis desktop (exactly the set the live session runs:
# the part of iso/packages.x86_64 above "@live-only", shipped on the ISO),
# build tools the AIOS backend needs, and the bundled [praxis] AUR packages.
# Hardware-specific packages (microcode, GPU drivers) are added by the caller.
praxis_packages() {
    local list=${PRAXIS_DESKTOP_LIST:-/usr/local/share/praxis/desktop-packages.txt}
    [ -f "$list" ] || { echo "praxis_packages: missing $list" >&2; return 1; }
    printf '%s\n' base base-devel linux linux-firmware sudo mkinitcpio grub efibootmgr \
        openssh git vim nano python-pip python-virtualenv qt5-wayland \
        tesseract tesseract-data-eng llama-cpp ggml-vulkan
    grep -vE '^[[:space:]]*(#|$)' "$list"
    [ -d "${PRAXIS_REPO_DIR:-/opt/praxis-repo}" ] && printf '%s\n' piper-tts-bin yay-bin mpvpaper
    return 0
}

# praxis_enable_local_repo — let pacstrap (which uses the live system's
# pacman.conf) see the [praxis] repository bundled on the ISO
praxis_enable_local_repo() {
    [ -d /opt/praxis-repo ] || return 0
    grep -q '^\[praxis\]' /etc/pacman.conf || cat >>/etc/pacman.conf <<'EOF'

[praxis]
SigLevel = Optional TrustAll
Server = file:///opt/praxis-repo
EOF
}

# praxis_copy_assets <target root>
# Copies everything that makes an installed system "Praxis" from the live
# image onto the target: tools, their library, user services, completions,
# branding (plus the tmpfiles rule that re-asserts it after `filesystem`
# package updates), the AIOS backend, and the bundled [praxis] repository.
praxis_copy_assets() {
    local root=$1 f src=${PRAXIS_SRC:-}    # PRAXIS_SRC: a staged image tree (tests), default: this live system

    install -d "$root/usr/local/bin"
    for f in "$src"/usr/local/bin/praxis* "$src"/usr/local/bin/aios-*; do
        [ -e "$f" ] || continue
        case "${f##*/}" in
            praxis-live-setup|praxis-install-window|praxis-install|praxis-install-*|aios-install*) continue ;;   # live media only
        esac
        cp -a "$f" "$root/usr/local/bin/"
    done

    for f in /usr/local/lib/praxis \
             /usr/local/share/aios \
             /usr/lib/praxis \
             /usr/lib/tmpfiles.d/praxis.conf \
             /usr/lib/systemd/user/praxis-first-boot.service \
             /usr/lib/systemd/user/praxis-genie.service \
             /usr/lib/systemd/user/aios.service.d \
             /usr/lib/systemd/user/swaync.service.d \
             /usr/lib/tmpfiles.d/praxis-memory.conf \
             /etc/sysctl.d/80-praxis-memory.conf \
             /etc/default/earlyoom \
             /usr/share/bash-completion/completions/praxis \
             /usr/share/zsh/site-functions/_praxis \
             /etc/systemd/zram-generator.conf \
             /etc/motd /etc/issue /etc/os-release; do
        [ -e "$src$f" ] || continue
        install -d "$root$(dirname "$f")"
        cp -a "$src$f" "$root$f"
    done
    # /usr/lib/os-release is a tmpfiles symlink on the live system; write the
    # real file so the branding is correct even before tmpfiles runs.
    [ -f "$src/usr/lib/praxis/os-release" ] && install -m644 "$src/usr/lib/praxis/os-release" "$root/usr/lib/os-release"

    [ -d "$src/opt/aios" ] && cp -a "$src/opt/aios" "$root/opt/aios"

    local repo=${PRAXIS_REPO_DIR:-/opt/praxis-repo}
    if [ -d "$repo" ]; then
        install -d "$root/opt/praxis-repo"
        cp -a "$repo/." "$root/opt/praxis-repo/"
        grep -q '^\[praxis\]' "$root/etc/pacman.conf" || cat >>"$root/etc/pacman.conf" <<'EOF'

[praxis]
SigLevel = Optional TrustAll
Server = file:///opt/praxis-repo
EOF
    fi

    [ -d "$src/etc/skel" ] && cp -a "$src/etc/skel/." "$root/etc/skel/"
}

# praxis_app_bundles — the optional app bundles the installers offer:
#   id|title|one-line description|packages (official repositories only)
praxis_app_bundles() {
    cat <<'BUNDLES'
office|Office|LibreOffice: documents, spreadsheets, slides — opens Microsoft Office files|libreoffice-fresh hunspell hunspell-en_us
dev|Developer|VS Code (Code - OSS), Docker, Node.js, GitHub CLI|code docker docker-compose docker-buildx nodejs npm github-cli python-pipx
media|Media|VLC, OBS Studio (record & stream), Audacity|vlc obs-studio audacity
creative|Creative|GIMP, Inkscape, Krita, Kdenlive|gimp inkscape krita kdenlive
gaming|Gaming|Steam, Lutris, GameMode, MangoHud (+ 32-bit drivers)|steam lutris gamemode lib32-gamemode mangohud lib32-mangohud
browsers|More browsers|Chromium next to Firefox|chromium
chat|Chat|Discord, Telegram|discord telegram-desktop
tools|Utilities|Disks, GParted, KeePassXC password manager, archive manager|gnome-disk-utility gparted keepassxc file-roller
BUNDLES
}

# praxis_bundle_pkgs <bundle id…> [-- <GPU driver packages>]
#   → packages for those bundles, one per line. Gaming adds the 32-bit
#   variants of this machine's GPU drivers (Steam's games are 32-bit).
praxis_bundle_pkgs() {
    local ids=() gpu=() id seen_gpu=0 p
    while [ $# -gt 0 ]; do
        if [ "$1" = -- ]; then shift; gpu=("$@"); break; fi
        ids+=("$1"); shift
    done
    for id in "${ids[@]}"; do
        praxis_app_bundles | awk -F'|' -v id="$id" '$1 == id { n = split($4, a, " "); for (i = 1; i <= n; i++) print a[i] }'
        if [ "$id" = gaming ] && [ "$seen_gpu" = 0 ]; then
            seen_gpu=1
            for p in "${gpu[@]}"; do
                case "$p" in
                    nvidia-utils)   echo lib32-nvidia-utils ;;
                    vulkan-intel)   echo lib32-vulkan-intel ;;
                    vulkan-radeon)  echo lib32-vulkan-radeon ;;
                    vulkan-nouveau) echo lib32-vulkan-nouveau ;;
                    mesa)           echo lib32-mesa ;;
                esac
            done
        fi
    done | awk '!seen[$0]++'
}

# praxis_target_services — system services every Praxis install enables
praxis_target_services() {
    printf '%s\n' NetworkManager bluetooth power-profiles-daemon systemd-timesyncd earlyoom fstrim.timer
}
