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
    local root=$1 f

    install -d "$root/usr/local/bin"
    for f in /usr/local/bin/praxis* /usr/local/bin/aios-*; do
        case "${f##*/}" in
            praxis-live-setup|praxis-install-window) continue ;;   # live media only
        esac
        cp -a "$f" "$root/usr/local/bin/"
    done

    for f in /usr/local/lib/praxis \
             /usr/local/share/aios \
             /usr/lib/praxis \
             /usr/lib/tmpfiles.d/praxis.conf \
             /usr/lib/systemd/user/praxis-first-boot.service \
             /usr/lib/systemd/user/praxis-genie.service \
             /usr/share/bash-completion/completions/praxis \
             /usr/share/zsh/site-functions/_praxis \
             /etc/systemd/zram-generator.conf \
             /etc/motd /etc/issue /etc/os-release; do
        [ -e "$f" ] || continue
        install -d "$root$(dirname "$f")"
        cp -a "$f" "$root$f"
    done
    # /usr/lib/os-release is a tmpfiles symlink on the live system; write the
    # real file so the branding is correct even before tmpfiles runs.
    [ -f /usr/lib/praxis/os-release ] && install -m644 /usr/lib/praxis/os-release "$root/usr/lib/os-release"

    [ -d /opt/aios ] && cp -a /opt/aios "$root/opt/aios"

    if [ -d /opt/praxis-repo ]; then
        install -d "$root/opt/praxis-repo"
        cp -a /opt/praxis-repo/. "$root/opt/praxis-repo/"
        grep -q '^\[praxis\]' "$root/etc/pacman.conf" || cat >>"$root/etc/pacman.conf" <<'EOF'

[praxis]
SigLevel = Optional TrustAll
Server = file:///opt/praxis-repo
EOF
    fi

    [ -d /etc/skel ] && cp -a /etc/skel/. "$root/etc/skel/"
}
