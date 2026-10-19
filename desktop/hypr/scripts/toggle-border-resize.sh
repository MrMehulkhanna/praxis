#!/usr/bin/env bash
# Toggle Hyprland border-drag window resizing (the hover resize-arrow) on/off at runtime.
# Bound to SUPER+SHIFT+B. Default (from hyprland.lua) is ON; this flips it for the
# current session — reload/reboot returns to the hyprland.lua default.
cur=$(hyprctl getoption general:resize_on_border 2>/dev/null | awk '/^bool:/ {print $2}')
if [ "$cur" = "true" ]; then
    new=false; msg="Border-drag resize: OFF"
else
    new=true;  msg="Border-drag resize: ON"
fi
hyprctl eval "hl.config({ general = { resize_on_border = $new } })" >/dev/null 2>&1
command -v notify-send >/dev/null 2>&1 && notify-send -t 1500 "Window resize" "$msg"
