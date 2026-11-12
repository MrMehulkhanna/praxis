"""
Tool gateway: the ONLY place a model-proposed command touches the system.

propose()  — local model turns natural language into ONE structured operation,
             policy classifies it, auto-tier runs directly via subprocess_exec
             (NEVER through bash -c), confirm-tier is parked behind a
             cryptographically random, one-time token, forbidden is refused.
execute()  — runs a parked confirm-tier command once by token, consuming it atomically.
"""

import asyncio
import hashlib
import json
import os
import re
import secrets
import shutil
import signal
import time
from typing import Dict, List, Tuple, Optional

from core.store import db
from core.perms import policy

CONFIRM_WINDOW_S = 60
MAX_OUTPUT_BYTES = 65536  # 64 KB limit to prevent memory exhaustion

_pending: Dict[str, dict] = {}    # token -> {cmd, argv, tier, expires_at, request, request_id, action_hash}

PROMPT = (
    "You control an Arch Linux desktop (Hyprland, PipeWire, brightnessctl, "
    "playerctl, hyprctl, nmcli, bluetoothctl). Convert the user's request into "
    "exactly ONE command line. Output only the command — no explanation, "
    "no markdown, no comments. Never use sudo. To launch an app, output just its "
    "executable name (firefox, kitty, thunar, antigravity, code). "
    "Volume: wpctl set-volume @DEFAULT_AUDIO_SINK@ 40%  (mute: wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle). "
    "Brightness: brightnessctl set 60%. Workspace: hyprctl dispatch hl.dsp.focus({ workspace = 3 }). "
    "Media: playerctl play-pause|next|previous. Lock: hyprlock. "
    "If the request is not something a shell command can do, output exactly: NOOP"
    "\n\nRequest: "
)

SECRET_ENV = re.compile(r"(API_?KEY|_TOKEN$|^AIOS_TOKEN$|SECRET|PASSWORD|_PAT$|CREDENTIAL|AUTH)", re.IGNORECASE)

SAFE_ENV_VARS = {
    "PATH", "HOME", "USER", "LANG", "LC_ALL", "LC_CTYPE",
    "DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "XDG_SESSION_TYPE",
    "XDG_CURRENT_DESKTOP", "DBUS_SESSION_BUS_ADDRESS", "TERM"
}

def _clean_env() -> Dict[str, str]:
    """Sanitize environment: whitelist safe variables and strip secrets."""
    clean = {}
    for k, v in os.environ.items():
        if k in SAFE_ENV_VARS or (k.startswith("XDG_") and not SECRET_ENV.search(k)):
            if not SECRET_ENV.search(k):
                clean[k] = v
    if "PATH" not in clean:
        clean["PATH"] = "/usr/local/bin:/usr/bin:/bin"
    return clean

def _strip_fences(s: str) -> str:
    s = s.strip()
    # Strip <think> reasoning blocks from thinking models
    s = re.sub(r"<think>.*?</think>", "", s, flags=re.IGNORECASE | re.DOTALL).strip()
    s = re.sub(r"^```[a-zA-Z]*\s*", "", s)
    s = re.sub(r"\s*```$", "", s)
    s = re.sub(r"^\$\s+", "", s)
    return s.strip().splitlines()[0].strip() if s.strip() else ""

def _audit(actor: str, action: str, args: str, decision: str, result: str):
    try:
        db.conn().execute(
            "INSERT INTO audit (actor, action, args_hash, decision, result, at) VALUES (?,?,?,?,?,?)",
            (actor, action, hashlib.sha256(args.encode()).hexdigest()[:16], decision, result[:2000], time.time()),
        )
        db.conn().commit()
    except Exception:
        pass

async def _run_argv(argv: List[str], timeout: float = 20.0) -> Tuple[int, str]:
    """
    Direct structured process execution using create_subprocess_exec.
    NEVER passes model strings to bash -c.
    Enforces process-group cleanup, bounded timeouts, and output limits.
    """
    if not argv:
        return 1, "Empty command line"

    binary = argv[0]
    # Check binary exists
    resolved = shutil.which(binary)
    if not resolved:
        return 127, f"Executable not found: {binary}"

    env = _clean_env()
    try:
        proc = await asyncio.create_subprocess_exec(
            resolved, *argv[1:],
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            env=env,
            start_new_session=True,  # Isolate in its own process group
        )
    except Exception as e:
        return 1, f"Failed to start process: {e}"

    try:
        out_bytes, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        code = proc.returncode if proc.returncode is not None else 0
        if len(out_bytes) > MAX_OUTPUT_BYTES:
            out_str = out_bytes[:MAX_OUTPUT_BYTES].decode(errors="replace") + "\n...[output truncated]"
        else:
            out_str = out_bytes.decode(errors="replace").strip()
        return code, out_str
    except asyncio.TimeoutError:
        # Terminate entire process group
        try:
            pgid = os.getpgid(proc.pid)
            os.killpg(pgid, signal.SIGTERM)
            await asyncio.sleep(0.3)
            os.killpg(pgid, signal.SIGKILL)
        except Exception:
            pass
        return 0, "(process running in background or timed out)"

def _sweep():
    now = time.time()
    for k in [k for k, v in _pending.items() if v["expires_at"] < now]:
        _pending.pop(k, None)

async def propose(request: str, adapter, model: str, classify_fn=None, jid: str | None = None) -> dict:
    from core.gateway.iface import Request as GReq
    classify_fn = classify_fn or policy.classify

    greq = GReq(
        system="You are a precise Linux command generator.",
        messages=[{"role": "user", "content": PROMPT + request}],
        model=model, max_tokens=120, temperature=0.1,
    )
    parts = []
    from core import activity
    tokens = adapter.run(greq)
    async for tok in (activity.guard(jid, tokens) if jid else tokens):
        parts.append(tok)
    cmd = _strip_fences("".join(parts))

    if not cmd or cmd.upper() == "NOOP":
        _audit("model", "propose", request, "noop", "")
        return {"cmd": "", "tier": "noop", "reason": "Nothing to run for that request.",
                "executed": False, "output": "", "token": None}

    tier, reason = classify_fn(cmd)
    tokens, err = policy.parse_argv(cmd)

    if tier == "forbidden" or not tokens:
        _audit("model", cmd, request, "deny", reason)
        return {"cmd": cmd, "tier": "forbidden", "reason": reason, "executed": False,
                "output": "", "token": None}

    if tier == "auto":
        code, out = await _run_argv(tokens)
        _audit("model", cmd, request, "allow", f"rc={code} {out}")
        return {"cmd": cmd, "tier": tier, "reason": reason, "executed": True,
                "output": out, "rc": code, "token": None}

    # Confirm tier: park behind a cryptographically random, one-time token
    _sweep()
    token = secrets.token_urlsafe(32)
    _pending[token] = {
        "cmd": cmd,
        "argv": tokens,
        "tier": tier,
        "request": request,
        "request_id": jid or secrets.token_hex(8),
        "action_hash": hashlib.sha256((cmd + request).encode()).hexdigest(),
        "created_at": time.time(),
        "expires_at": time.time() + CONFIRM_WINDOW_S
    }
    _audit("model", cmd, request, "prompt", reason)
    return {"cmd": cmd, "tier": tier, "reason": reason, "executed": False,
            "output": "", "token": token}

async def execute(token: str, expected_request_id: Optional[str] = None) -> dict:
    """
    Executes a parked confirm-tier command once by token.
    Consumes token atomically to prevent replay attacks.
    """
    _sweep()
    p = _pending.pop(token, None)
    if not p:
        return {
            "executed": False,
            "output": "Confirmation token is invalid, expired, or has already been used.",
            "cmd": "",
            "rc": 1
        }

    if expected_request_id and p.get("request_id") != expected_request_id:
        return {
            "executed": False,
            "output": "Token binding mismatch: token is not valid for this session/request.",
            "cmd": "",
            "rc": 1
        }

    # Safety re-check: even confirmed commands cannot execute shell interpreters or forbidden binaries
    forbidden, why = policy.is_forbidden(p["cmd"], p.get("argv"))
    if forbidden:
        _audit("user", p["cmd"], p["request"], "deny_confirmed", why)
        return {"executed": False, "output": f"Refused: {why}", "cmd": p["cmd"], "rc": 1}

    code, out = await _run_argv(p["argv"])
    _audit("user", p["cmd"], p["request"], "confirmed", f"rc={code} {out}")
    return {"executed": True, "output": out, "cmd": p["cmd"], "rc": code}

def cancel(token: str) -> bool:
    p = _pending.pop(token, None)
    if p:
        _audit("user", p["cmd"], p["request"], "cancelled", "")
    return bool(p)
