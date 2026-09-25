"""
Tool gateway: the ONLY place a model-proposed command touches the system.

propose()  — local model turns natural language into ONE shell command,
             policy classifies it, auto-tier runs, confirm-tier is parked
             behind a short-lived token, forbidden is refused. Always audited.
execute()  — runs a parked confirm-tier command once, by token.
"""
import asyncio, hashlib, json, os, re, time, uuid
from core.store import db

CONFIRM_WINDOW_S = 60
_pending: dict[str, dict] = {}    # token -> {cmd, tier, expires_at, request}

PROMPT = (
    "You control an Arch Linux desktop (Hyprland, PipeWire, brightnessctl, "
    "playerctl, hyprctl, nmcli, bluetoothctl). Convert the user's request into "
    "exactly ONE bash command line. Output only the command — no explanation, "
    "no markdown, no comments. Never use sudo. To launch an app, output just its "
    "executable name (firefox, kitty, thunar, antigravity, code). "
    "Volume: wpctl set-volume @DEFAULT_AUDIO_SINK@ 40%  (mute: wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle). "
    "Brightness: brightnessctl set 60%. Workspace: hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })'. "
    "Media: playerctl play-pause|next|previous. Lock: hyprlock. "
    "If the request is not something a shell command can do, output exactly: NOOP"
    "\n\nRequest: "
)

def _strip_fences(s: str) -> str:
    s = s.strip()
    # Qwen-family derivatives can emit a reasoning block even when thinking is
    # disabled. Commands must be parsed from the answer after that block, never
    # from its private reasoning text.
    s = re.sub(r"<think>.*?</think>", "", s, flags=re.IGNORECASE | re.DOTALL).strip()
    s = re.sub(r"^```[a-zA-Z]*\s*", "", s)
    s = re.sub(r"\s*```$", "", s)
    # models sometimes prefix with '$ '
    s = re.sub(r"^\$\s+", "", s)
    return s.strip().splitlines()[0].strip() if s.strip() else ""

def _audit(actor: str, action: str, args: str, decision: str, result: str):
    db.conn().execute(
        "INSERT INTO audit (actor, action, args_hash, decision, result, at) VALUES (?,?,?,?,?,?)",
        (actor, action, hashlib.sha256(args.encode()).hexdigest()[:16], decision, result[:2000], time.time()),
    )
    db.conn().commit()

async def _run(cmd: str, timeout: float = 20.0) -> tuple[int, str]:
    env = {**os.environ}
    proc = await asyncio.create_subprocess_exec(
        "bash", "-lc", cmd,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
        env=env, start_new_session=True,
    )
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        # GUI apps never exit — that's fine; they were launched. Detach and move on.
        return 0, "(running in background)"
    return proc.returncode or 0, out.decode(errors="replace").strip()

def _sweep():
    now = time.time()
    for k in [k for k, v in _pending.items() if v["expires_at"] < now]:
        _pending.pop(k, None)

async def propose(request: str, adapter, model: str, classify) -> dict:
    from core.gateway.iface import Request as GReq
    greq = GReq(
        system="You are a precise Linux command generator.",
        messages=[{"role": "user", "content": PROMPT.replace("{request}", request)}],
        model=model, max_tokens=120, temperature=0.1,
    )
    parts = []
    async for tok in adapter.run(greq):
        parts.append(tok)
    cmd = _strip_fences("".join(parts))
    if not cmd or cmd.upper() == "NOOP":
        _audit("model", "propose", request, "noop", "")
        return {"cmd": "", "tier": "noop", "reason": "Nothing to run for that request.",
                "executed": False, "output": "", "token": None}

    tier, reason = classify(cmd)
    if tier == "forbidden":
        _audit("model", cmd, request, "deny", reason)
        return {"cmd": cmd, "tier": tier, "reason": reason, "executed": False,
                "output": "", "token": None}

    if tier == "auto":
        code, out = await _run(cmd)
        _audit("model", cmd, request, "allow", f"rc={code} {out}")
        return {"cmd": cmd, "tier": tier, "reason": reason, "executed": True,
                "output": out, "rc": code, "token": None}

    _sweep()
    token = uuid.uuid4().hex[:12]
    _pending[token] = {"cmd": cmd, "tier": tier, "request": request,
                       "expires_at": time.time() + CONFIRM_WINDOW_S}
    _audit("model", cmd, request, "prompt", reason)
    return {"cmd": cmd, "tier": tier, "reason": reason, "executed": False,
            "output": "", "token": token}

async def execute(token: str) -> dict:
    _sweep()
    p = _pending.pop(token, None)
    if not p:
        return {"executed": False, "output": "Confirmation expired or unknown. Ask again.",
                "cmd": "", "rc": 1}
    code, out = await _run(p["cmd"])
    _audit("user", p["cmd"], p["request"], "confirmed", f"rc={code} {out}")
    return {"executed": True, "output": out, "cmd": p["cmd"], "rc": code}

def cancel(token: str) -> bool:
    p = _pending.pop(token, None)
    if p:
        _audit("user", p["cmd"], p["request"], "cancelled", "")
    return bool(p)
