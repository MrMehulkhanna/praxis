"""
Risk classification for model-proposed shell commands.

Three tiers, mirroring voice/security.py so the whole system has one
permission vocabulary:

  auto      — runs immediately (launch an app, adjust volume, read-only info)
  confirm   — shown to the user first; runs only after an explicit confirm
  forbidden — never runs, regardless of confirmation

Default is `confirm`, not `auto`: a command has to positively match a safe
pattern to run without asking. Unknown = ask.
"""
import re, shlex

FORBIDDEN = [
    (r"\brm\s+(-[a-zA-Z]*r[a-zA-Z]*\s+)?(/|~|\$HOME|\*)\s*$", "recursive delete of a root path"),
    (r"\brm\s+-[a-zA-Z]*r[a-zA-Z]*f|\brm\s+-[a-zA-Z]*f[a-zA-Z]*r", "forced recursive delete"),
    (r"\b(mkfs|fdisk|parted|wipefs|dd)\b", "disk/partition destruction"),
    (r":\(\)\s*\{.*\};\s*:", "fork bomb"),
    (r"\bsudo\b|\bdoas\b|\bsu\b\s", "privilege escalation (needs a password anyway)"),
    (r"\bchmod\s+(-R\s+)?[0-7]*7[0-7]*7\b", "world-writable permissions"),
    (r"\bchown\s+-R\s+\S+\s+/\s*$", "recursive chown of /"),
    (r"(curl|wget)\b[^|]*\|\s*(ba)?sh\b", "piping a download into a shell"),
    (r"\b(shutdown|poweroff|halt|init\s+0)\b", "power off — use the power menu / voice confirm"),
    (r">\s*/dev/(sd|nvme|mmc)", "writing to a block device"),
    (r"\b(pacman|yay|paru)\s+-R", "package removal"),
    (r"\bhistory\s+-c\b|\bshred\b", "evidence destruction"),
    (r"\.ssh/|\.gnupg/|aios\.env|api[_-]?key", "touching secrets"),
]

# Positive allow-list: only these run without asking.
AUTO = [
    r"^(wpctl|pactl|pamixer)\s",
    r"^brightnessctl\s",
    r"^playerctl\s",
    r"^hyprctl\s+dispatch\s+'?hl\.dsp\.(focus|layout|window\.(move|float|fullscreen|pseudo|center|pin))\b",
    r"^hyprctl\s+(-j\s+)?(monitors|workspaces|clients|activewindow|devices|version|getoption|layers|binds)\b",
    r"^notify-send\s",
    r"^xdg-open\s",
    r"^(firefox|chromium|google-chrome-stable|brave|kitty|alacritty|foot|thunar|nautilus|dolphin|code|antigravity|pavucontrol|blueman-manager|nm-connection-editor|rofi|grim|swaync-client|hyprlock|hyprpicker|wl-copy|wl-paste)\b",
    r"^(ls|cat|head|tail|grep|rg|find|fd|wc|du|df|free|uptime|date|cal|whoami|hostname|uname|lscpu|lsblk|lsusb|lspci|ip\s+(a|addr|link|route)|ss|nvidia-smi|sensors|top\s+-bn1|ps|pgrep|which|echo|printf|env|printenv|systemctl\s+(--user\s+)?(status|list-units|is-active)|journalctl|nmcli\s+(d|dev|device|c|con|connection|g|general|r|radio)\s+(show|status|list|wifi\s+list)|bluetoothctl\s+(devices|info|show|paired-devices))\b",
    r"^(git\s+(status|log|diff|branch|show|remote|stash\s+list))\b",
    r"^(python3?|node)\s+-c\s",
    r"^(curl|wget)\s+-[sSfL]*\s*https?://127\.0\.0\.1",
]

def classify(cmd: str) -> tuple[str, str]:
    """Returns (tier, reason)."""
    c = cmd.strip()
    if not c:
        return "forbidden", "empty command"
    for pat, why in FORBIDDEN:
        if re.search(pat, c, re.IGNORECASE):
            return "forbidden", why
    # a chain/pipe is judged by every segment; the riskiest wins
    segments = [s.strip() for s in re.split(r"\s*(?:\|\||&&|;|\|)\s*", c) if s.strip()]
    def _safe(s: str) -> bool:
        # read-only commands stop being read-only once their output is redirected
        stripped = re.sub(r"2>\s*(&1|/dev/null)", "", s)
        if re.search(r">|\btee\b", stripped):
            return False
        return any(re.match(p, s) for p in AUTO)
    if all(_safe(s) for s in segments):
        return "auto", "matches safe allow-list"
    return "confirm", "not on the safe list — needs your confirmation"

def argv(cmd: str) -> list[str]:
    """Safe tokenisation for logging/display; execution still goes via bash -c."""
    try:
        return shlex.split(cmd)
    except ValueError:
        return [cmd]
