# Start the Praxis desktop (Hyprland via uwsm) automatically on the first console.
[[ -f ~/.bashrc ]] && . ~/.bashrc

if [[ -z "${WAYLAND_DISPLAY:-}" && "$(tty)" == "/dev/tty1" ]]; then
    # The setup wizard is for installed systems. On live media the desktop
    # starts immediately and the dock offers "Install Praxis Linux" instead.
    if [[ ! -d /run/archiso && -x /usr/local/bin/praxis-welcome ]]; then
        /usr/local/bin/praxis-welcome
    fi
    if command -v uwsm >/dev/null && uwsm check may-start >/dev/null 2>&1; then
        exec uwsm start hyprland.desktop
    else
        exec Hyprland
    fi
fi
