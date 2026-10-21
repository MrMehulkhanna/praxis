# Start the Praxis desktop (Hyprland via uwsm) automatically on the first console.
[[ -f ~/.bashrc ]] && . ~/.bashrc

if [[ -z "${WAYLAND_DISPLAY:-}" && "$(tty)" == "/dev/tty1" ]]; then
    # Auto-detect multi-GPU (e.g. Intel/AMD iGPU + NVIDIA dGPU) so external monitor ports work
    if [ -d /dev/dri/by-path ]; then
        igpu=$(ls /dev/dri/by-path/*-card 2>/dev/null | grep -E '00:02\.0|amd|integrated' | head -1 || true)
        dgpu=$(ls /dev/dri/by-path/*-card 2>/dev/null | grep -v "$igpu" | head -1 || true)
        if [ -n "$igpu" ] && [ -n "$dgpu" ]; then
            export AQ_DRM_DEVICES="$igpu:$dgpu"
        fi
    fi
    # The desktop starts straight away; its welcome notification offers to set
    # up the AI (the installer already asked for everything else). The old
    # text wizard is still there as `praxis welcome`.
    if command -v uwsm >/dev/null && uwsm check may-start >/dev/null 2>&1; then
        exec uwsm start hyprland.desktop
    else
        exec Hyprland
    fi
fi
