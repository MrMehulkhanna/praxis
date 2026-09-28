# shellcheck shell=bash
# Shared by praxis-install and praxis-install-partition.

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
