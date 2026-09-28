"""
Terminal agent: answers system questions with evidence.

  question → classify → gather relevant read-only diagnostics (auto-tier
  only) → model answers; may ask for ONE more read-only command per round
  (RUN: …) or propose a fix (FIX: …) that the user must confirm.

Everything is emitted to the activity bus so the user can watch it happen.
"""
import glob, json, re, time
from core import activity, router
from core.perms import policy
from core.tools import exec as tools
from core.store import db

MAX_ROUNDS = 3
GATHER_CAP = 7000

DIAG = [
    (r"\b(gpu|nvidia|cuda|vram|graphics|display driver|rtx)\b",
     ["nvidia-smi", "lspci -k | grep -A3 -iE 'vga|3d'", "lsmod | grep -iE 'nvidia|nouveau|i915|xe'",
      "journalctl -b -p err --no-pager -n 40 | grep -iE 'nvidia|drm|gpu'"]),
    (r"\b(boot|kernel|dmesg|crash|freeze|frozen|hang|panic)\b",
     ["journalctl -b -p 3 --no-pager -n 40", "systemctl --failed --no-pager", "uname -a"]),
    (r"\b(service|systemd|systemctl|daemon|unit)\b",
     ["systemctl --failed --no-pager", "systemctl --user --failed --no-pager"]),
    (r"\b(wifi|wi-fi|network|internet|dns|ethernet|connect|ping|nmcli|ip address)\b",
     ["nmcli d", "nmcli g", "ip -br a", "resolvectl status | head -20"]),
    (r"\b(audio|sound|mic|microphone|speaker|pipewire|volume|headphone)\b",
     ["wpctl status | head -45"]),
    (r"\b(disk|storage|space|nvme|ssd|mount|partition|full)\b",
     ["df -h -x tmpfs -x devtmpfs -x efivarfs", "lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT"]),
    (r"\b(memory|ram|swap|oom|out of memory)\b",
     ["free -h", "ps -eo pid,pmem,rss,comm --sort=-rss | head -8"]),
    (r"\b(cpu|slow|lag|performance|temp|temperature|fan|thermal|throttl|hot|load)\b",
     ["uptime", "sensors", "cat /sys/firmware/acpi/platform_profile", "ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -8"]),
    (r"\b(battery|charg|power draw|drain)\b",
     ["cat /sys/class/power_supply/BAT0/capacity /sys/class/power_supply/BAT0/status", "powerprofilesctl get"]),
    (r"\b(bluetooth|bt |pair)\b", ["bluetoothctl show | head -12", "bluetoothctl devices"]),
    (r"\b(hyprland|wayland|window|monitor|screen|workspace|compositor)\b",
     ["hyprctl monitors", "hyprctl version | head -2", "journalctl --user -b -p err --no-pager -n 20"]),
    (r"\b(package|pacman|install|update|upgrade)\b", ["pacman -Q | wc -l", "pacman -Qu | head -15"]),
    (r"\b(python|pip|venv|module)\b", ["python3 --version", "which python3", "pip --version"]),
    (r"\b(aios|llama|model|whisper|voice)\b",
     ["systemctl --user status aios.service --no-pager | head -8", "curl -s -m 2 http://127.0.0.1:8778/api/status", "ls ~/aios/models"]),
]

def _machine() -> tuple[str, str]:
    """(laptop|computer, its GPUs) — the agent must not assume one particular machine's hardware."""
    from core import hardware
    kind = "laptop" if glob.glob("/sys/class/power_supply/BAT*") else "computer"
    return kind, " + ".join(hardware.gpus()) or "an unknown GPU"

_KIND, _GPUS = _machine()
SYSTEM = (
    f"You are the AI assistant built into Praxis Linux, running on the user's own Arch-based {_KIND} "
    "(Hyprland with a Lua config — options via hyprctl eval 'hl.config{…}', dispatch via hyprctl dispatch 'hl.dsp.…' — "
    f"PipeWire, NetworkManager, {_GPUS}, systemd). "
    "Diagnostic command outputs are provided as evidence — base your answer on them, quote the "
    "relevant lines, and be concrete. Keep answers short and practical.\n"
    "If you need the output of ONE more read-only command to answer, finish your reply with a "
    "single final line exactly like:  RUN: <command>\n"
    "If the fix requires changing the system, do NOT run it — finish with a single final line:  "
    "FIX: <command>   (the user will be asked to confirm). Never use sudo in FIX lines; "
    "the system handles privileges."
)

def _diagnostics_for(text: str) -> list[str]:
    t = text.lower()
    cmds: list[str] = []
    for pat, cs in DIAG:
        if re.search(pat, t):
            for c in cs:
                if c not in cmds:
                    cmds.append(c)
    if not cmds:
        cmds = ["uname -a", "uptime"]
    return cmds[:8]

async def _gather(jid: str, cmds: list[str]) -> str:
    parts, total = [], 0
    for c in cmds:
        tier, why = policy.classify(c)
        if tier != "auto":
            activity.emit(jid, "skipped", f"not read-only: {c} ({why})")
            continue
        activity.emit(jid, "gather", c)
        rc, out = await tools._run(c, timeout=8)
        out = out.strip() or "(no output)"
        if len(out) > 2500:
            out = out[:1200] + "\n…\n" + out[-1200:]
        block = f"$ {c}\n{out}\n"
        if total + len(block) > GATHER_CAP:
            break
        parts.append(block); total += len(block)
    return "\n".join(parts)

def _strip_tail(text: str) -> tuple[str, str | None, str | None]:
    """Returns (answer_without_directive, run_cmd, fix_cmd)."""
    lines = text.rstrip().split("\n")
    run = fix = None
    while lines:
        last = lines[-1].strip()
        m = re.match(r"^(RUN|FIX):\s*`?(.+?)`?\s*$", last)
        if not m:
            break
        if m.group(1) == "RUN" and run is None:
            run = m.group(2)
        elif m.group(1) == "FIX" and fix is None:
            fix = m.group(2)
        lines.pop()
    return "\n".join(lines).rstrip(), run, fix

async def run(question: str, adapter, model: str, mode: str, reason: str, conversation_id: str,
              engine, GReq, think: bool = False, images: list | None = None):
    """Async generator yielding SSE lines."""
    jid = activity.new_job("agent", question, model=model, mode=mode)
    cls = router.classify(question)
    activity.emit(jid, "classified", f"{cls['task']} task", task=cls["task"])
    activity.emit(jid, "routed", f"{model} · {mode} · {reason}", model=model, mode=mode)
    yield f"event: meta\ndata: {json.dumps({'model': model, 'mode': mode, 'task': cls['task'], 'reason': reason, 'job': jid})}\n\n"

    uid = db.add_object("message", question, conversation_id=conversation_id, role="user")
    evidence = ""
    if cls["diagnostic"]:
        cmds = _diagnostics_for(question)
        evidence = await _gather(jid, cmds)
        yield f"event: step\ndata: {json.dumps({'stage': 'gathered', 'msg': f'{len(cmds)} diagnostics collected'})}\n\n"

    pkg = engine.build(question, conversation_id, ctx_window=6144)
    transcript: list[dict] = pkg["turns"]
    user_block = question if not evidence else f"{question}\n\n<diagnostics>\n{evidence}\n</diagnostics>"
    transcript = transcript + [{"role": "user", "content": user_block}]
    full_answer = []
    t0 = time.time()
    status, err = "ok", None

    for rnd in range(MAX_ROUNDS):
        if activity.stopped(jid):
            status = "cancelled"
            break
        activity.emit(jid, "generate", f"round {rnd + 1} · {model}")
        yield f"event: step\ndata: {json.dumps({'stage': 'generate', 'msg': f'{model} is answering'})}\n\n"
        greq = GReq(system=SYSTEM + ("\n\n" + engine.render_system(pkg, model).split("<retrieved_context>")[-1] if pkg["retrieved"] else ""),
                    messages=transcript, model=model, max_tokens=700, temperature=0.3, think=think,
                    images=(images or []) if rnd == 0 else [])
        buf = []
        try:
            async for tok in activity.guard(jid, adapter.run(greq)):
                buf.append(tok)
                yield f"data: {json.dumps(tok)}\n\n"
        except activity.Cancelled:
            status = "cancelled"
            full_answer.append("".join(buf))
            yield f"data: {json.dumps(chr(10) * 2 + '⏹ stopped')}\n\n"
            break
        except Exception as e:
            status, err = "error", str(e)
            activity.emit(jid, "error", str(e))
            yield f"event: error\ndata: {json.dumps(str(e))}\n\n"
            break
        text = "".join(buf)
        answer, run_cmd, fix_cmd = _strip_tail(text)
        full_answer.append(answer)
        transcript.append({"role": "assistant", "content": text})

        if fix_cmd:
            tier, why = policy.classify(fix_cmd)
            if tier == "forbidden":
                activity.emit(jid, "refused", f"{fix_cmd} — {why}")
                yield f"event: step\ndata: {json.dumps({'stage': 'refused', 'msg': f'proposed fix refused: {why}', 'cmd': fix_cmd})}\n\n"
            else:
                tools._sweep()
                token = __import__("uuid").uuid4().hex[:12]
                tools._pending[token] = {"cmd": fix_cmd, "tier": "confirm", "request": question,
                                         "expires_at": time.time() + 300}
                tools._audit("model", fix_cmd, question, "prompt", "agent FIX proposal")
                activity.emit(jid, "approval", f"awaiting confirmation: {fix_cmd}")
                yield f"event: pending\ndata: {json.dumps({'cmd': fix_cmd, 'token': token, 'reason': 'proposed fix — changes the system', 'tier': 'confirm'})}\n\n"
            break
        if run_cmd and rnd < MAX_ROUNDS - 1:
            tier, why = policy.classify(run_cmd)
            if tier == "auto":
                activity.emit(jid, "execute", run_cmd)
                yield f"event: step\ndata: {json.dumps({'stage': 'execute', 'msg': run_cmd})}\n\n"
                rc, out = await tools._run(run_cmd, timeout=10)
                tools._audit("model", run_cmd, question, "allow", f"rc={rc} {out[:300]}")
                out = (out.strip() or "(no output)")[:2500]
                yield f"data: {json.dumps(chr(10) + chr(10))}\n\n"
                transcript.append({"role": "user", "content": f"$ {run_cmd}\n{out}\n\nContinue your answer."})
                continue
            activity.emit(jid, "approval", f"needs confirmation: {run_cmd}")
            tools._sweep()
            token = __import__("uuid").uuid4().hex[:12]
            tools._pending[token] = {"cmd": run_cmd, "tier": "confirm", "request": question, "expires_at": time.time() + 300}
            yield f"event: pending\ndata: {json.dumps({'cmd': run_cmd, 'token': token, 'reason': why, 'tier': 'confirm'})}\n\n"
        break

    final = "\n\n".join(a for a in full_answer if a)
    if final:
        aid = db.add_object("message", final, conversation_id=conversation_id, role="assistant")
        db.link(aid, uid, "answers")
    db.log_run(provider="local" if mode == "LOCAL" else model.split("/")[0], model=model, capability="agent",
               conversation_id=conversation_id, context_ids_json=json.dumps(pkg["ids"]),
               in_tok=pkg["tokens"] + db.est_tokens(evidence), out_tok=db.est_tokens(final),
               cost_est=0.0, ms=int((time.time() - t0) * 1000), status=status, error=err)
    activity.end_job(jid, ok=status == "ok")
    yield "event: done\ndata: {}\n\n"
