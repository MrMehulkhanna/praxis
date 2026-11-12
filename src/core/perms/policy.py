"""
Risk classification and structured validation for model-proposed commands.

Three tiers:
  auto      — runs immediately (strictly validated allowlisted binary and arguments)
  confirm   — shown to the user first; runs only after an explicit cryptographic token confirmation
  forbidden — never runs, regardless of confirmation

Default is `confirm`, not `auto`: a command has to positively match a safe,
structured, allowlisted schema to run without asking. Unknown = ask.
"""

import re
import shlex
from typing import Tuple, List, Optional

# Characters that execute subshells or substitutions
SUBSHELL_CHARS = re.compile(r"[`$]|<\(|>\(")

# Forbidden destructive, privilege escalation, or secret access patterns
FORBIDDEN_PATTERNS = [
    (r"\brm\s+(-[a-zA-Z]*r[a-zA-Z]*\s+)?(/|~|\$HOME|\*)\s*$", "recursive delete of a root path"),
    (r"\brm\s+-[a-zA-Z]*r[a-zA-Z]*f|\brm\s+-[a-zA-Z]*f[a-zA-Z]*r", "forced recursive delete"),
    (r"\b(mkfs|fdisk|parted|wipefs|dd)\b", "disk/partition destruction"),
    (r":\(\)\s*\{.*\};\s*:", "fork bomb"),
    (r"\b(sudo|doas|su|pkexec)\b", "privilege escalation"),
    (r"\bchmod\s+(-R\s+)?[0-7]*7[0-7]*7\b", "world-writable permissions"),
    (r"\bchown\s+-R\s+\S+\s+/\s*$", "recursive chown of /"),
    (r"(curl|wget)\b[^|]*\|\s*(ba)?sh\b", "piping a download into a shell"),
    (r"\b(shutdown|poweroff|halt|init\s+0)\b", "power off — use power menu"),
    (r">\s*/dev/(sd|nvme|mmc)", "writing to a block device"),
    (r"\b(pacman|yay|paru)\s+-R", "package removal"),
    (r"\b(history\s+-c|shred)\b", "evidence destruction"),
    (r"(\.ssh/|\.gnupg/|aios\.env|aios\.token|api[_-]?key|/etc/shadow|/etc/sudoers)", "touching secrets"),
    (r"\b(find|fd|xargs|grep|rg)\b[^|;&]*(-exec(dir)?\b|-delete\b|-fprintf?\b|--?(ok|okdir)\b)", "find/xargs running another command"),
    (r"\b(env|printenv)\b", "would print backend environment, including cloud API keys"),
    (r"\b(bash|sh|zsh|dash|csh|tcsh|ksh)\b", "direct shell interpreter invocation"),
    (r"\b(python|python3|perl|ruby|php|node)\s+-c\b", "inline script interpreter execution"),
]

# Allowlisted desktop apps for launch
AUTO_APPS = {
    "firefox", "chromium", "google-chrome-stable", "brave",
    "kitty", "alacritty", "foot", "thunar", "nautilus", "dolphin",
    "code", "antigravity", "pavucontrol", "blueman-manager",
    "nm-connection-editor", "rofi", "grim", "swaync-client",
    "hyprlock", "hyprpicker", "wl-copy", "wl-paste"
}

# Positive allow-list regex patterns for safe single commands
AUTO_PATTERNS = [
    r"^(wpctl|pactl|pamixer)\s",
    r"^brightnessctl\s",
    r"^playerctl\s",
    r"^hyprctl\s+dispatch\s+'?hl\.dsp\.(focus|layout|window\.(move|float|fullscreen|pseudo|center|pin))\b",
    r"^hyprctl\s+(-j\s+)?(monitors|workspaces|clients|activewindow|devices|version|getoption|layers|binds)\b",
    r"^notify-send\s",
    r"^xdg-open\s+https?://",
    r"^(ls|cat|head|tail|grep|rg|find|fd|wc|du|df|free|uptime|date|cal|whoami|hostname|uname|lscpu|lsblk|lsusb|lspci|ip\s+(a|addr|link|route)|ss|nvidia-smi|sensors|top\s+-bn1|ps|pgrep|which|echo|printf|systemctl\s+(--user\s+)?(status|list-units|is-active)|journalctl|nmcli\s+(d|dev|device|c|con|connection|g|general|r|radio)\s+(show|status|list|wifi\s+list)|bluetoothctl\s+(devices|info|show|paired-devices))\b",
    r"^(git\s+(status|log|diff|branch|show|remote|stash\s+list))\b",
    r"^(curl|wget)\s+-[sSfL]*\s*https?://127\.0\.0\.1",
]

def parse_argv(cmd: str) -> Tuple[Optional[List[str]], Optional[str]]:
    """Safely tokenizes a command string into structured argv."""
    c = cmd.strip()
    if not c:
        return None, "empty command"
    try:
        tokens = shlex.split(c)
        if not tokens:
            return None, "empty command"
        return tokens, None
    except ValueError as e:
        return None, f"syntax error in command: {e}"

def is_forbidden(cmd: str, argv: Optional[List[str]] = None) -> Tuple[bool, str]:
    """Check if command matches any forbidden pattern or touches forbidden binaries/paths."""
    for pat, reason in FORBIDDEN_PATTERNS:
        if re.search(pat, cmd, re.IGNORECASE):
            return True, reason

    if argv:
        binary = argv[0].lower().split("/")[-1]
        if binary in ("sudo", "su", "doas", "pkexec"):
            return True, "privilege escalation"
        if binary in ("bash", "sh", "zsh", "dash", "ksh"):
            return True, "invoking shell interpreter directly"
        if binary in ("mkfs", "fdisk", "parted", "dd", "wipefs"):
            return True, "disk/partition destruction"
        if binary == "rm" and any(arg in ("/", "/*", "~", "$HOME") for arg in argv[1:]):
            return True, "recursive delete of critical path"

    return False, ""

def classify(cmd: str) -> Tuple[str, str]:
    """
    Classifies command into (tier, reason).
    Only strictly validated single-process allowlisted operations can be 'auto'.
    """
    c = cmd.strip()
    if not c:
        return "forbidden", "empty command"

    # Any subshell or command substitution requires confirmation
    if SUBSHELL_CHARS.search(c):
        return "confirm", "contains subshell or process substitution — needs your confirmation"

    # Check forbidden rules
    forbidden, why = is_forbidden(c)
    if forbidden:
        return "forbidden", why

    # Commands with sequential chaining (&&, ||, ;, &) or newlines cannot auto-run
    # Splitting on chaining operators to check segments
    chain_split = re.split(r"\s*(?:\|\||&&|;|&|\n|\r)\s*", c)
    if len(chain_split) > 1:
        # Multiple commands chained together — requires confirmation
        return "confirm", "contains command chaining or background execution — requires confirmation"

    # Pipes (|) are allowed ONLY between safe read-only commands (e.g. ps aux | grep llama)
    pipe_segments = [s.strip() for s in c.split("|") if s.strip()]

    def _is_safe_segment(s: str) -> bool:
        # Redirection (> or < or tee) strips read-only safety
        stripped = re.sub(r"2>\s*(&1|/dev/null)", "", s)
        if re.search(r"[><]|\btee\b", stripped):
            return False
        # Strip environment prefixes like LD_PRELOAD
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", s):
            return False
        # Apps from AUTO_APPS are safe
        first_word = s.split()[0].lower().split("/")[-1]
        if first_word in AUTO_APPS:
            return True
        return any(re.match(p, s) for p in AUTO_PATTERNS)

    if all(_is_safe_segment(seg) for seg in pipe_segments):
        return "auto", "matches safe allow-list"

    return "confirm", "not on the safe auto allow-list — needs explicit confirmation"

def argv(cmd: str) -> List[str]:
    """Safe tokenisation for logging/display."""
    tokens, err = parse_argv(cmd)
    return tokens if tokens else [cmd]
