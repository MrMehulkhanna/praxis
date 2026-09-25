# Hyprland integration

This shell targets Hyprland with the **Lua** config format (`hyprland.lua`). Add to your config:

```lua
-- autostart
hl.on("hyprland.start", function ()
  hl.exec_cmd("quickshell -d -p ~/.config/quickshell/shell.qml")
  hl.exec_cmd("swaync &")
  hl.exec_cmd("hyprpaper &")
  hl.exec_cmd("systemctl --user start aios.service")
  hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
end)

-- frosted glass on the shell's layer surfaces
hl.layer_rule({ name = "quickshell-glass", match = { namespace = "^quickshell$" }, blur = true, ignore_alpha = 0.1 })

-- panel toggles (Super + A/I/O/W)
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("quickshell ipc call shell toggle launcher"))
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("quickshell ipc call shell toggle ai"))
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("quickshell ipc call shell toggle cc"))
```

Note: this Lua parser does **not** accept `hyprctl keyword`; use `hyprctl eval 'hl.config{…}'`
and `hyprctl dispatch 'hl.dsp.…'`. The shell already does this internally.
