#!/usr/bin/env python3
"""
security.py — the ONLY place voice input turns into a system action.

Design, in order of importance:

1. DEFAULT DENY. A transcript is checked against voice_permissions.json.
   No match = refused and logged. There is no fallback path that executes
   something the manifest didn't explicitly authorize.

2. NO DYNAMIC COMMAND CONSTRUCTION FROM SPEECH. Every handler below takes
   fixed, code-defined arguments (or a numeric capture group that's
   range-checked, e.g. volume/brightness/workspace). The transcript is
   NEVER interpolated into a shell string and NEVER passed to eval/exec.
   The "open app" handler resolves through the manifest's `apps` dict —
   voice can say an app's name, never an arbitrary path or command.

3. TIERED EXECUTION. "auto" commands run immediately. "confirm" commands
   (suspend/reboot/shutdown/logout) do NOT run on the first utterance —
   they arm a short-lived pending confirmation that must be explicitly
   confirmed with a second, separate voice press. This means a single
   misheard phrase can never suspend or reboot the machine.

4. EVERYTHING IS LOGGED. Every transcript that reaches this gate — matched
   or not, executed or refused — is appended to voice_audit.jsonl. You can
   audit exactly what voice ever did or attempted, at any time.

5. UNMATCHED SPEECH GOES TO THE AI AS A QUESTION ONLY. AIOS has no tool-
   calling / system-execution capability wired in (by design, per its own
   architecture) — it can only stream back text. So even if a transcript
   doesn't match any command and gets forwarded to AIOS, the worst case
   is it answers a question. It cannot act on your system.
"""
import json, os, re, subprocess, sys, time, pathlib

AIOS_HOME = pathlib.Path(os.environ.get("AIOS_HOME", pathlib.Path.home() / "aios"))
MANIFEST_PATH = pathlib.Path(__file__).parent / "voice_permissions.json"
AUDIT_LOG = AIOS_HOME / "logs" / "voice_audit.jsonl"
PENDING_FILE = pathlib.Path("/tmp/aios-voice-pending-confirm.json")
CONFIRM_WINDOW_S = 20  # generous but bounded — must be the very next utterance

CONFIRM_WORDS = {"yes", "confirm", "do it", "confirmed", "yeah do it"}
CANCEL_WORDS  = {"no", "cancel", "never mind", "stop"}


# ── manifest loading ──────────────────────────────────────────────────────
def _load_manifest() -> dict:
    with open(MANIFEST_PATH) as f:
        return json.load(f)


# ── audit log — append-only, every event, no exceptions ───────────────────
def _audit(event: dict):
    AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
    event["ts"] = time.time()
    with open(AUDIT_LOG, "a") as f:
        f.write(json.dumps(event) + "\n")


# ── fixed handler dispatch table — the ONLY code paths that touch the system
def _run(cmd: list[str]) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except Exception as e:
        return f"error: {e}"

def _h_volume_set(m, manifest):
    pct = max(0, min(100, int(m.group(3))))       # range-checked, never raw
    _run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{pct}%"])
    return f"Volume set to {pct} percent"

def _h_volume_up(m, manifest):
    _run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+"])
    return "Volume up"

def _h_volume_down(m, manifest):
    _run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"])
    return "Volume down"

def _h_mute_toggle(m, manifest):
    _run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    return "Toggled mute"

def _h_brightness_set(m, manifest):
    pct = max(1, min(100, int(m.group(3))))
    _run(["brightnessctl", "set", f"{pct}%"])
    return f"Brightness set to {pct} percent"

def _h_brightness_up(m, manifest):
    _run(["brightnessctl", "set", "+10%"])
    return "Brightness up"

def _h_brightness_down(m, manifest):
    _run(["brightnessctl", "set", "10%-"])
    return "Brightness down"

def _h_workspace_switch(m, manifest):
    ws = max(1, min(20, int(m.group(2))))
    _run(["hyprctl", "dispatch", f"hl.dsp.focus({{ workspace = {ws} }})"])
    return f"Switched to workspace {ws}"

def _h_open_app(m, manifest):
    # NOTE: the app names allowed to match here are hardcoded in the
    # open_app pattern in voice_permissions.json AND must exist as keys in
    # manifest["apps"] below. Adding an app means editing BOTH — the
    # pattern's alternation (what voice is allowed to *say*) and the apps
    # dict (what actually *runs*). This duplication is intentional: it
    # means an app can never become launchable by voice through a single
    # careless edit to just one of the two places.
    spoken = m.group(2).strip().lower()
    apps = manifest.get("apps", {})
    cmd = apps.get(spoken)
    if not cmd:
        return f"'{spoken}' isn't in the allowed app list"
    subprocess.Popen(["bash", "-lc", cmd])
    return f"Opening {spoken}"

def _h_unload_model(m, manifest):
    _run(["curl", "-sX", "POST", "http://127.0.0.1:8778/api/unload"])
    return "Model unloaded, VRAM freed"

def _h_lock_screen(m, manifest):
    subprocess.Popen(["hyprlock"])
    return "Locking"

def _h_suspend(m, manifest):
    subprocess.Popen(["systemctl", "suspend"])
    return "Suspending"

def _h_logout(m, manifest):
    _run(["hyprctl", "dispatch", "hl.dsp.exit()"])
    return "Logging out"

def _h_reboot(m, manifest):
    subprocess.Popen(["systemctl", "reboot"])
    return "Rebooting"

def _h_shutdown(m, manifest):
    subprocess.Popen(["systemctl", "poweroff"])
    return "Shutting down"

def _h_help(m, manifest):
    descs = [c["description"] for c in manifest["commands"]
             if c["tier"] != "forbidden"]
    return "You can say: " + "; ".join(descs)

# ── backend-backed handlers (all read-only or allow-listed setters) ─────
import urllib.request as _ur

def _api(path, data=None, timeout=8):
    body = json.dumps(data).encode() if data is not None else None
    req = _ur.Request("http://127.0.0.1:8778" + path, data=body,
                      headers={"Content-Type": "application/json"} if body else {})
    with _ur.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())

_ctx = {"cmd": None, "text": ""}   # set by route() right before a handler runs

def _cmd_arg(m, manifest, handler_default=None):
    # the matched manifest entry carries a fixed 'arg' — never derived from speech
    c = _ctx.get("cmd") or {}
    return c.get("arg", handler_default)

def _h_model_select(m, manifest):
    arg = _cmd_arg(m, manifest, "auto")
    try:
        s = _api("/api/settings", {"selected_model": arg})
        names = {"auto": "automatic routing", "local-qwen3-4b": "the fast model, Qwen 3 4B",
                 "local-qwen3-8b": "the quality model, Qwen 3 8B", "local-coder-7b": "the coding model"}
        return "Switched to " + names.get(s["selected_model"], s["selected_model"])
    except Exception as e:
        return f"Couldn't switch model: {e}"

def _h_model_which(m, manifest):
    try:
        s = _api("/api/status")
        sel = s["selected_model"]; loaded = s.get("loaded") or "nothing"
        return f"Selected model is {sel.replace('local-', '').replace('-', ' ')}; {loaded.replace('local-', '').replace('-', ' ')} is loaded in VRAM."
    except Exception as e:
        return f"Backend not reachable: {e}"

def _hw():
    return _api("/api/hardware")

def _safe(fn):
    def w(m, manifest):
        try:
            return fn(m, manifest)
        except Exception as e:
            return f"I couldn't read that from the backend: {str(e)[:60]}"
    return w

def _h_status_gpu(m, manifest):
    g = _hw()["gpu"]
    if not g.get("present"): return "No NVIDIA GPU detected"
    return f"GPU at {int(g['util'] or 0)} percent, {int(g['vram_used_mb'] or 0)} of {int(g['vram_total_mb'] or 0)} megabytes of VRAM used, {int(g['temp_c'] or 0)} degrees"

def _h_status_cpu(m, manifest):
    c = _hw()["cpu"]
    return f"CPU at {int(c['usage'])} percent, {c['temp_c']} degrees, load {c['load'][0]}"

def _h_status_mem(m, manifest):
    r = _hw()["memory"]
    return f"Memory {round(r['used'] / 1e9, 1)} of {round(r['total'] / 1e9, 1)} gigabytes used, {int(r['percent'])} percent"

def _h_status_bat(m, manifest):
    b = _hw()["battery"]
    if not b.get("present"): return "No battery"
    return f"Battery {b['percent']} percent, {b['status'].lower()}" + (", on AC power" if b.get("ac") else "")

def _h_status_disk(m, manifest):
    fs = [f for f in _hw()["storage"]["filesystems"] if f["mount"] == "/"]
    if not fs: return "No root filesystem info"
    f = fs[0]
    return f"{round(f['avail'] / 1e9)} gigabytes free of {round(f['size'] / 1e9)}, {f['percent']} percent used"

def _h_status_temp(m, manifest):
    t = _hw()["temps"]
    return ", ".join(f"{k} {v} degrees" for k, v in t.items()) or "No temperature sensors"

def _h_perf_mode(m, manifest):
    text = (_ctx.get("text") or "").lower()
    p = "performance" if "performance" in text else "power-saver" if ("quiet" in text or "power" in text) else "balanced"
    _api("/api/hardware/set", {"what": "profile", "value": p})
    return f"{p.replace('-', ' ')} mode"

def _h_svc(m, manifest):
    arg = _cmd_arg(m, manifest, "")
    if arg not in ("restart aios.service", "stop aios.service", "start aios.service"):
        return "That service isn't allowed"
    subprocess.Popen(["systemctl", "--user", *arg.split()])
    return f"{arg.split()[0].capitalize()}ing the AI backend"

def _h_dev_env(m, manifest):
    apps = manifest.get("apps", {})
    for key in ("terminal", "code", "antigravity", "browser"):
        if key in apps:
            subprocess.Popen(["bash", "-lc", apps[key]])
    return "Starting your development environment"

def _h_panel(m, manifest):
    arg = _cmd_arg(m, manifest, "ai")
    subprocess.Popen(["quickshell", "ipc", "call", "shell", "open", arg])
    return f"Opening {arg}"

HANDLERS = {
    "volume_set": _h_volume_set, "volume_up": _h_volume_up,
    "volume_down": _h_volume_down, "mute_toggle": _h_mute_toggle,
    "brightness_set": _h_brightness_set, "brightness_up": _h_brightness_up,
    "brightness_down": _h_brightness_down, "workspace_switch": _h_workspace_switch,
    "open_app": _h_open_app, "unload_model": _h_unload_model,
    "lock_screen": _h_lock_screen, "suspend": _h_suspend, "logout": _h_logout,
    "reboot": _h_reboot, "shutdown": _h_shutdown, "help": _h_help,
    "model_select": _h_model_select, "model_which": _h_model_which,
    "status_gpu": _safe(_h_status_gpu), "status_cpu": _safe(_h_status_cpu), "status_mem": _safe(_h_status_mem),
    "status_bat": _safe(_h_status_bat), "status_disk": _safe(_h_status_disk), "status_temp": _safe(_h_status_temp),
    "perf_mode": _safe(_h_perf_mode), "svc": _h_svc, "dev_env": _h_dev_env, "panel": _h_panel,
}


# ── pending confirmation state ──────────────────────────────────────────
def _read_pending():
    if not PENDING_FILE.exists():
        return None
    try:
        p = json.loads(PENDING_FILE.read_text())
    except Exception:
        return None
    if time.time() > p.get("expires_at", 0):
        PENDING_FILE.unlink(missing_ok=True)
        return None
    return p

def _arm_pending(command_id, match_groups, spoken_prompt):
    PENDING_FILE.write_text(json.dumps({
        "command_id": command_id,
        "groups": match_groups,
        "text": _ctx.get("text", ""),
        "expires_at": time.time() + CONFIRM_WINDOW_S,
    }))
    return spoken_prompt

def _clear_pending():
    PENDING_FILE.unlink(missing_ok=True)


# ── main entry point ──────────────────────────────────────────────────────
def route(transcript: str) -> dict:
    """Returns {"kind", "reply", "spoken", "executed": bool}"""
    manifest = _load_manifest()
    text = transcript.strip().lower().rstrip(".!?")

    if not text:
        return {"kind": "empty", "reply": "", "spoken": "", "executed": False}

    # ── resolve a pending confirmation first, before anything else ────────
    pending = _read_pending()
    if pending:
        if text in CONFIRM_WORDS:
            cmd = next((c for c in manifest["commands"]
                       if c["id"] == pending["command_id"]), None)
            _clear_pending()
            if not cmd:
                result = {"kind": "error", "reply": "Confirmed command no longer exists",
                          "spoken": None, "executed": False}
                _audit({"transcript": transcript, "kind": "confirm_stale"})
                return result
            handler = HANDLERS[cmd["handler"]]
            fake_match = _FakeMatch(pending["groups"])
            _ctx["cmd"], _ctx["text"] = cmd, pending.get("text", "")
            reply = handler(fake_match, manifest)
            _audit({"transcript": transcript, "kind": "confirmed_execute",
                    "command_id": cmd["id"], "reply": reply})
            return {"kind": "command", "reply": reply, "spoken": reply, "executed": True}
        elif text in CANCEL_WORDS:
            _clear_pending()
            _audit({"transcript": transcript, "kind": "confirm_cancelled"})
            return {"kind": "command", "reply": "Cancelled", "spoken": "Cancelled",
                    "executed": False}
        # anything else while a confirmation is pending: fall through and
        # treat as a brand new command (don't trap the user in confirm-mode
        # forever if they change their mind and say something else)
        _clear_pending()

    # ── match against the allow-list, nothing else ─────────────────────────
    for c in manifest["commands"]:
        if c["tier"] == "forbidden":
            continue  # forbidden entries exist as documentation, never match
        m = re.match(c["pattern"], text)
        if not m:
            continue

        if c["tier"] == "auto":
            handler = HANDLERS[c["handler"]]
            _ctx["cmd"], _ctx["text"] = c, text
            reply = handler(m, manifest)
            _audit({"transcript": transcript, "kind": "auto_execute",
                    "command_id": c["id"], "reply": reply})
            return {"kind": "command", "reply": reply, "spoken": reply, "executed": True}

        if c["tier"] == "confirm":
            prompt = f"Say 'confirm' to {c['description'].split(' — ')[0]}, or 'cancel'."
            _ctx["cmd"], _ctx["text"] = c, text
            _arm_pending(c["id"], list(m.groups()), prompt)
            _audit({"transcript": transcript, "kind": "confirm_armed",
                    "command_id": c["id"]})
            return {"kind": "confirm_pending", "reply": prompt, "spoken": prompt,
                    "executed": False}

    # ── nothing matched — refuse if it LOOKS like a command attempt,
    #     otherwise treat as a genuine question for the AI ─────────────────
    COMMAND_LIKE = re.compile(
        r"^(run|execute|delete|remove|rm |sudo|chmod|kill|install|uninstall|"
        r"format|wipe|write to|overwrite)\b"
    )
    if COMMAND_LIKE.match(text):
        _audit({"transcript": transcript, "kind": "refused_unauthorized"})
        return {"kind": "refused",
                "reply": "That's not an authorized voice command.",
                "spoken": "That's not an authorized voice command.",
                "executed": False}

    _audit({"transcript": transcript, "kind": "forwarded_to_ai"})
    return {"kind": "question", "reply": transcript, "spoken": None, "executed": False}


class _FakeMatch:
    """Replays captured groups from the original match when a confirm-tier
    command is actually executed on the second utterance."""
    def __init__(self, groups):
        self._groups = groups
    def group(self, i):
        return self._groups[i - 1]
    def groups(self):
        return tuple(self._groups)


if __name__ == "__main__":
    result = route(" ".join(sys.argv[1:]))
    print(json.dumps(result))
