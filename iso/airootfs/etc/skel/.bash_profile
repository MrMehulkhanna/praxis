# Start the Praxis desktop (Hyprland via uwsm) automatically on the first console.
[[ -f ~/.bashrc ]] && . ~/.bashrc

if [[ -z "${WAYLAND_DISPLAY:-}" && "$(tty)" == "/dev/tty1" ]]; then
    # The desktop starts straight away; its welcome notification offers to set
    # up the AI (the installer already asked for everything else). The old
    # text wizard is still there as `praxis welcome`.
    if command -v uwsm >/dev/null && uwsm check may-start >/dev/null 2>&1; then
        exec uwsm start hyprland.desktop
    else
        exec Hyprland
    fi
fi
