"""AIOS — FastAPI server. One process, everything inside."""
import asyncio, json, os, pathlib, time
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse, FileResponse
from pydantic import BaseModel

from core.store  import db
from core.context import engine
from core.gateway.iface import Request as GReq
from core.gateway import gate
from core.perms import policy
from core.tools import exec as tools
from core import activity, router, providers, hardware, agent, rag
from core.voice import transcribe as stt
from adapters.local.llama import LlamaAdapter, list_models, PROFILES, DEFAULT_MODEL

UI_FILE = pathlib.Path(__file__).parent / "ui" / "index.html"
LOCAL: LlamaAdapter | None = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global LOCAL
    db.conn()
    LOCAL = LlamaAdapter()
    providers.init(LOCAL)
    tasks = [asyncio.create_task(LOCAL._reaper()), asyncio.create_task(stt.reaper())]
    activity.emit(None, "system", "AIOS backend started")
    yield
    for t in tasks: t.cancel()
    await LOCAL.unload_now()

app = FastAPI(title="AIOS", lifespan=lifespan)

# ── model registry / selection ──────────────────────────────────────────
def measured_speed() -> dict[str, dict]:
    """Effective tokens/sec per model — median of the last 20 real replies."""
    out: dict[str, dict] = {}
    rows = db.conn().execute(
        "SELECT model, out_tok, ms FROM runs WHERE status='ok' AND out_tok >= 20 AND ms > 0 "
        "AND capability IN ('chat','agent') ORDER BY created_at DESC").fetchall()
    per: dict[str, list] = {}
    for r in rows:
        per.setdefault(r["model"], []).append((r["out_tok"] * 1000.0 / r["ms"], r["ms"]))
    for model, samples in per.items():
        samples = samples[:20]
        rates = sorted(s[0] for s in samples); mid = len(rates) // 2
        median = rates[mid] if len(rates) % 2 else (rates[mid - 1] + rates[mid]) / 2
        out[model] = {"tok_per_s": round(median, 1), "avg_reply_ms": int(sum(s[1] for s in samples) / len(samples)), "runs": len(samples)}
    return out

def registry(is_online: bool | None = None) -> list[dict]:
    speed = measured_speed()
    sel = selected_model()
    out = []
    for m in providers.registry(list_models(), is_online):
        m["measured"] = speed.get(m["id"])
        m["selected"] = (m["id"] == sel)
        out.append(m)
    return out

def selected_model() -> str:
    m = db.kv_get("selected_model", DEFAULT_MODEL)
    return m if (m == "auto" or m in PROFILES or "/" in m) else DEFAULT_MODEL

# friendly aliases so IDE / CLI configs stay readable
ALIASES = {"aios": "auto", "aios-auto": "auto", "aios-code": "local-coder-7b", "aios-coder": "local-coder-7b",
           "aios-fast": "local-qwen3-4b", "aios-daily": "local-qwen3-4b", "aios-quality": "local-qwen3-8b",
           "aios-vision": "local-qwen3-vl-8b", "aios-vl": "local-qwen3-vl-8b",
           "aios-unfiltered": "local-dolphin-v2-8b", "aios-dolphin": "local-dolphin-v2-8b"}

def resolve(requested: str | None, text: str = "", loaded: str | None = None, needs_vision: bool = False) -> dict:
    """→ {model, provider, mode, reason, task}. Honors explicit ids; routes 'auto'."""
    if requested in ALIASES:
        requested = ALIASES[requested]
    want = requested if requested and requested != "auto" else selected_model()
    cls = router.classify(text) if text else {"task": "general", "tokens": 0}
    if needs_vision and want != "auto":
        info = next((m for m in registry(False) if m["id"] == want), {})
        if not info.get("vision"):
            want = "auto"   # explicit model can't see; route to one that can
    if want == "auto":
        net = providers.online()
        r = router.choose(cls["task"], registry(net), loaded, gate.mode(), net,
                          router.prefer_cloud_for(), cls.get("tokens", 0), needs_vision=needs_vision)
        r["task"] = cls["task"]; r["auto"] = True
        return r
    prov = "local" if want.startswith("local-") else want.split("/", 1)[0]
    return {"model": want, "provider": prov, "mode": "LOCAL" if prov == "local" else "CLOUD",
            "reason": "selected manually", "task": cls["task"], "auto": False}

@app.get("/api/models")
def models():
    return registry()

@app.get("/api/route")
def route_preview(text: str = ""):
    return resolve(None, text, LOCAL._loaded if LOCAL else None)

@app.get("/api/settings")
def get_settings():
    return {
        "selected_model": selected_model(), "auto": selected_model() == "auto",
        "budget_mode": gate.mode(), "budget_modes": list(gate.MODES),
        "thinking": bool(db.kv_get("thinking", False)),
        "prefer_cloud_for": router.prefer_cloud_for(),
        "idle_unload": int(os.environ.get("AIOS_IDLE_UNLOAD", "120")),
    }

class SettingsPatch(BaseModel):
    selected_model:   str | None = None
    budget_mode:      str | None = None
    thinking:         bool | None = None
    prefer_cloud_for: list[str] | None = None

@app.post("/api/settings")
def set_settings(p: SettingsPatch):
    if p.selected_model is not None:
        ids = {m["id"] for m in registry(False)} | {"auto"}
        if p.selected_model not in ids:
            raise HTTPException(400, f"unknown model '{p.selected_model}'")
        db.kv_set("selected_model", p.selected_model)
        activity.emit(None, "settings", f"model → {p.selected_model}")
    if p.budget_mode is not None:
        try: gate.set_mode(p.budget_mode)
        except ValueError as e: raise HTTPException(400, str(e))
        activity.emit(None, "settings", f"budget → {p.budget_mode}")
    if p.thinking is not None:
        db.kv_set("thinking", bool(p.thinking))
    if p.prefer_cloud_for is not None:
        db.kv_set("prefer_cloud_for", [t for t in p.prefer_cloud_for if t in router.TASKS])
    return get_settings()

@app.post("/api/settings/approve")
def approve(data: dict):
    gate.approve_once(data.get("run_key", "next"))
    return {"approved": True}

# ── status / usage / providers ──────────────────────────────────────────
@app.get("/api/status")
def status():
    stats = db.db_stats()
    return {"loaded": LOCAL._loaded if LOCAL else None, "selected_model": selected_model(),
            "budget_mode": gate.mode(), "online": providers.online(), "whisper_loaded": stt.loaded(),
            "jobs": list(activity.jobs.values()), "idle_unload": os.environ.get("AIOS_IDLE_UNLOAD", "120"), **stats}

@app.get("/api/usage")
def usage():
    rows = db.conn().execute(
        "SELECT provider, model, COUNT(*) n, SUM(in_tok) in_tok, SUM(out_tok) out_tok, SUM(cost_est) cost, "
        "AVG(ms) avg_ms, SUM(CASE WHEN status!='ok' THEN 1 ELSE 0 END) failed, MAX(created_at) last "
        "FROM runs GROUP BY provider, model ORDER BY last DESC").fetchall()
    out = [{**dict(r), "mode": "LOCAL" if r["provider"] == "local" else "CLOUD",
            "failure_rate": round(r["failed"] / r["n"], 3) if r["n"] else 0, "quota": "n/a" if r["provider"] == "local" else "unknown"} for r in rows]
    tot = db.conn().execute("SELECT COUNT(*) n, SUM(in_tok) i, SUM(out_tok) o, SUM(cost_est) c FROM runs").fetchone()
    return {"by_model": out, "total": {"requests": tot["n"], "in_tok": tot["i"] or 0, "out_tok": tot["o"] or 0, "cost_est": tot["c"] or 0.0},
            "providers": providers.status_list()}

@app.get("/api/providers")
def provider_status():
    return providers.status_list()

@app.post("/api/providers/reload")
def provider_reload():
    providers.reload()
    return providers.status_list()

@app.post("/api/unload")
async def unload():
    if LOCAL: await LOCAL.unload_now()
    activity.emit(None, "system", "local model unloaded, VRAM freed")
    return {"unloaded": True}

# ── activity ────────────────────────────────────────────────────────────
@app.get("/api/activity")
def activity_recent(limit: int = 100):
    return {"events": activity.recent(limit), "jobs": list(activity.jobs.values())}

@app.get("/api/activity/stream")
async def activity_stream():
    return StreamingResponse(activity.stream(), media_type="text/event-stream")

# ── hardware ────────────────────────────────────────────────────────────
@app.get("/api/hardware")
def hw():
    return hardware.snapshot()

class HwSet(BaseModel):
    what: str
    value: str

@app.post("/api/hardware/set")
async def hw_set(p: HwSet):
    fn = {"profile": lambda v: hardware.set_platform_profile(v), "keyboard": lambda v: hardware.set_keyboard_backlight(int(v)),
          "charge_limit": lambda v: hardware.set_charge_limit(int(v)), "fan": lambda v: hardware.set_fan_mode(v)}.get(p.what)
    if not fn:
        raise HTTPException(400, "what must be profile|keyboard|charge_limit|fan")
    ok, msg = await asyncio.to_thread(fn, p.value)
    activity.emit(None, "hardware", f"{p.what} → {p.value}: {msg}")
    tools._audit("user", f"hardware {p.what}={p.value}", p.what, "allow" if ok else "deny", msg)
    return {"ok": ok, "message": msg}

# ── voice ───────────────────────────────────────────────────────────────
class Wav(BaseModel):
    path: str

@app.post("/api/voice/transcribe")
async def voice_transcribe(w: Wav):
    if not os.path.exists(w.path):
        raise HTTPException(404, "no such file")
    t0 = time.time()
    text = await stt.transcribe(w.path)
    activity.emit(None, "voice", f"heard: {text[:80]}" if text else "heard nothing", ms=int((time.time() - t0) * 1000))
    return {"text": text, "ms": int((time.time() - t0) * 1000)}

# ── conversation history / ledgers ──────────────────────────────────────
@app.get("/api/history/{conversation_id}")
def history(conversation_id: str, limit: int = 50):
    return [{"role": r["role"], "body": r["body"], "created_at": r["created_at"]} for r in db.recent_messages(conversation_id, limit=limit)]

@app.get("/api/runs")
def runs(limit: int = 30):
    return [dict(r) for r in db.conn().execute("SELECT * FROM runs ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()]

@app.get("/api/audit")
def audit(limit: int = 50):
    return [dict(r) for r in db.conn().execute("SELECT * FROM audit ORDER BY at DESC LIMIT ?", (limit,)).fetchall()]

@app.get("/api/projects")
def projects():
    return [dict(r) for r in db.conn().execute("SELECT * FROM projects ORDER BY last_used_at DESC").fetchall()]

@app.post("/api/projects")
def create_project(data: dict):
    pid = db.nid()
    db.conn().execute("INSERT INTO projects (id,name,path,description,created_at,last_used_at) VALUES (?,?,?,?,?,?)",
                      (pid, data.get("name", "Unnamed"), data.get("path"), data.get("description"), db.now(), db.now()))
    db.conn().commit()
    return {"id": pid}

# ── PC control: propose → (confirm) → execute ───────────────────────────
class ToolRequest(BaseModel):
    request: str

@app.post("/api/tool/propose")
async def tool_propose(req: ToolRequest):
    # routing/classification is ALWAYS local — never spend cloud tokens on it
    model = DEFAULT_MODEL if not (LOCAL and LOCAL._loaded in PROFILES) else LOCAL._loaded
    jid = activity.new_job("control", req.request, model=model, mode="LOCAL")
    t0 = time.time()
    try:
        activity.emit(jid, "generate", f"turning request into a command ({model})")
        result = await tools.propose(req.request, LOCAL, model, policy.classify)
        stage = {"auto": "executed", "confirm": "approval", "forbidden": "refused", "noop": "result"}.get(result["tier"], "result")
        activity.emit(jid, stage, result.get("cmd") or result.get("reason", ""))
        activity.end_job(jid, ok=result["tier"] != "forbidden", msg=result.get("output", "")[:120] or result["tier"])
        status_, err = "ok", None
    except Exception as e:
        result = {"cmd": "", "tier": "error", "reason": str(e), "executed": False, "output": "", "token": None}
        activity.end_job(jid, ok=False, msg=str(e)); status_, err = "error", str(e)
    db.log_run(provider="local", model=model, capability="tool", conversation_id="tool", context_ids_json="[]",
               in_tok=db.est_tokens(req.request), out_tok=db.est_tokens(result.get("cmd", "")),
               cost_est=0.0, ms=int((time.time() - t0) * 1000), status=status_, error=err)
    return result

class ToolToken(BaseModel):
    token: str

@app.post("/api/tool/exec")
async def tool_exec(t: ToolToken):
    r = await tools.execute(t.token)
    activity.emit(None, "executed" if r.get("executed") else "error", r.get("cmd") or r.get("output", ""))
    return r

@app.post("/api/tool/cancel")
def tool_cancel(t: ToolToken):
    activity.emit(None, "cancelled", "user cancelled a proposed command")
    return {"cancelled": tools.cancel(t.token)}

# ── chat ────────────────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    message:         str
    conversation_id: str  = "default"
    model:           str  = "auto"
    project_id:      str | None = None
    max_tokens:      int  = 1024
    temperature:     float = 0.7
    images:          list[str] = []

def _pick(req_model: str, text: str, images: list | None = None):
    r = resolve(req_model, text, LOCAL._loaded if LOCAL else None, needs_vision=bool(images))
    adapter = providers.adapter_for(r["model"]) if r["model"] else None
    return r, adapter

async def _err_stream(msg: str):
    yield f"event: error\ndata: {json.dumps(msg)}\n\n"
    yield "event: done\ndata: {}\n\n"

@app.post("/api/chat")
async def chat(req: ChatRequest):
    t0 = time.time()
    r, adapter = _pick(req.model, req.message, req.images)
    if not adapter or not r["model"]:
        return StreamingResponse(_err_stream(f"No usable model ({r.get('reason', 'none')})."), media_type="text/event-stream")
    model, cloud = r["model"], r["mode"] == "CLOUD"
    minfo = next((m for m in registry(False) if m["id"] == model), {})
    if cloud and not minfo.get("available", False):
        return StreamingResponse(_err_stream(f"'{model}' is not available: {minfo.get('note', 'provider not configured')}"), media_type="text/event-stream")

    jid = activity.new_job("chat", req.message, model=model, mode=r["mode"])
    activity.emit(jid, "classified", r["task"] + " task")
    activity.emit(jid, "routed", f"{model} · {r['mode']} · {r['reason']}")
    uid = db.add_object("message", req.message, conversation_id=req.conversation_id, project_id=req.project_id, role="user")

    ctx_window = minfo.get("ctx", 8192)
    pkg = engine.build(req.message, req.conversation_id, ctx_window=min(ctx_window, 32768), project_id=req.project_id)
    est_cost = providers.estimate_cost(model, pkg["tokens"] + db.est_tokens(req.message), req.max_tokens)
    try:
        gate.check(adapter, uid, est_cost, cloud=cloud, free=bool(minfo.get("free")))
    except gate.BudgetDenied as e:
        activity.end_job(jid, ok=False, msg="blocked by budget gate")
        return StreamingResponse(_err_stream(str(e)), media_type="text/event-stream")

    greq = GReq(system=engine.render_system(pkg, model), messages=pkg["turns"] + [{"role": "user", "content": req.message}],
                model=model, max_tokens=req.max_tokens, temperature=req.temperature, think=bool(db.kv_get("thinking", False)),
                images=req.images)

    async def sse():
        meta = {"event": "meta", "model": model, "mode": r["mode"], "task": r["task"], "reason": r["reason"], "auto": r.get("auto", False),
                "context_tokens": pkg["tokens"], "budget": pkg["budget"], "retrieved": len(pkg["retrieved"]), "job": jid}
        yield f"event: meta\ndata: {json.dumps(meta)}\n\n"
        activity.emit(jid, "generate", f"{model} is answering")
        parts, status_, err = [], "ok", ""
        try:
            async for tok in adapter.run(greq):
                parts.append(tok)
                yield f"data: {json.dumps(tok)}\n\n"
        except Exception as e:
            status_, err = "error", str(e)
            yield f"event: error\ndata: {json.dumps(err)}\n\n"
        full = "".join(parts)
        if full:
            aid = db.add_object("message", full, conversation_id=req.conversation_id, project_id=req.project_id, role="assistant")
            db.link(aid, uid, "answers")
        out_tok = db.est_tokens(full)
        db.log_run(provider=r["provider"] or "local", model=model, capability="chat", conversation_id=req.conversation_id,
                   context_ids_json=json.dumps(pkg["ids"]), in_tok=pkg["tokens"], out_tok=out_tok,
                   cost_est=providers.estimate_cost(model, pkg["tokens"], out_tok), ms=int((time.time() - t0) * 1000),
                   status=status_, error=err or None)
        activity.end_job(jid, ok=status_ == "ok", msg=err or f"{out_tok} tokens")
        yield "event: done\ndata: {}\n\n"
    return StreamingResponse(sse(), media_type="text/event-stream")

# ── terminal agent ──────────────────────────────────────────────────────
@app.post("/api/agent")
async def agent_endpoint(req: ChatRequest):
    r, adapter = _pick(req.model, req.message, req.images)
    if not adapter or not r["model"]:
        return StreamingResponse(_err_stream(f"No usable model ({r.get('reason', 'none')})."), media_type="text/event-stream")
    minfo = next((m for m in registry(False) if m["id"] == r["model"]), {})
    if r["mode"] == "CLOUD":
        try:
            gate.check(adapter, "agent", providers.estimate_cost(r["model"], 4000, 700), cloud=True, free=bool(minfo.get("free")))
        except gate.BudgetDenied as e:
            return StreamingResponse(_err_stream(str(e)), media_type="text/event-stream")
        if not minfo.get("available"):
            return StreamingResponse(_err_stream(f"'{r['model']}' unavailable: {minfo.get('note')}"), media_type="text/event-stream")
    return StreamingResponse(
        agent.run(req.message, adapter, r["model"], r["mode"], r["reason"], req.conversation_id, engine, GReq,
                  think=bool(db.kv_get("thinking", False)), images=req.images),
        media_type="text/event-stream")

# ── unified entry: agent when the question is about the machine, chat otherwise ──
@app.post("/api/ask")
async def ask(req: ChatRequest):
    cls = router.classify(req.message)
    if cls["diagnostic"] and not req.images:
        return await agent_endpoint(req)
    return await chat(req)

# ── OpenAI-compatible gateway for coding tools ──────────────────────────
# Point Continue / Cline / Aider / Zed / any OpenAI client at
# http://127.0.0.1:8778/v1 (any api key). It goes through the same routing
# and cost gate, but does NOT touch the personal memory graph — an IDE sends
# its own file context, so we pass the messages straight through.
def _oai_model_list():
    data = [{"id": "auto", "object": "model", "created": int(time.time()), "owned_by": "aios",
             "aios": {"role": "router", "note": "picks the best available model per request"}}]
    for alias in ("aios-code", "aios-fast", "aios-quality", "aios-vision", "aios-unfiltered"):
        data.append({"id": alias, "object": "model", "created": int(time.time()), "owned_by": "aios",
                     "aios": {"role": "alias", "maps_to": ALIASES[alias]}})
    for m in registry():
        if m["available"]:
            data.append({"id": m["id"], "object": "model", "created": int(time.time()),
                         "owned_by": m["provider"],
                         "aios": {"role": m["role"], "vision": m.get("vision", False),
                                  "quality": m["quality"], "ctx": m["ctx"], "where": "local" if m["provider"] == "local" else ("free" if m.get("free") else "paid")}})
    return data

@app.get("/v1/models")
def oai_models():
    data = _oai_model_list()
    # `data` for OpenAI clients; `models` so Codex CLI's model-refresh is happy too
    return {"object": "list", "data": data, "models": [{"name": m["id"], "model": m["id"]} for m in data]}

@app.get("/api/tags")   # Ollama-compatible discovery (some tools probe this)
def ollama_tags():
    return {"models": [{"name": m["id"], "model": m["id"]} for m in _oai_model_list()]}

class OAIRequest(BaseModel):
    model: str = "auto"
    messages: list
    stream: bool = False
    max_tokens: int | None = None
    temperature: float = 0.4
    top_p: float | None = None

def _oai_extract(messages: list) -> tuple[str, list, str]:
    """→ (system, non-system messages, last user text for routing)."""
    system, rest, last_user = "", [], ""
    for m in messages:
        role = m.get("role")
        content = m.get("content", "")
        text = content if isinstance(content, str) else " ".join(
            p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text")
        if role == "system":
            system = (system + "\n" + text).strip() if system else text
        else:
            rest.append(m)
            if role == "user":
                last_user = text
    return system, rest, last_user

@app.post("/v1/chat/completions")
async def oai_chat(req: OAIRequest):
    system, msgs, last_user = _oai_extract(req.messages)
    # coding tools mostly want code → bias routing toward the code model, but honour an explicit id
    r = resolve(req.model, last_user, LOCAL._loaded if LOCAL else None,
                needs_vision=any(isinstance(m.get("content"), list) for m in msgs))
    model = r["model"]
    adapter = providers.adapter_for(model) if model else None
    if not adapter or not model:
        raise HTTPException(503, f"no usable model ({r.get('reason', 'none')})")
    minfo = next((m for m in registry(False) if m["id"] == model), {})
    cloud = r["mode"] == "CLOUD"
    if cloud and not minfo.get("available"):
        raise HTTPException(503, f"'{model}' unavailable: {minfo.get('note')}")
    try:
        gate.check(adapter, "oai", providers.estimate_cost(model, db.est_tokens(last_user), req.max_tokens or 1024),
                   cloud=cloud, free=bool(minfo.get("free")))
    except gate.BudgetDenied as e:
        raise HTTPException(402, str(e))

    greq = GReq(system=system or "You are a precise coding assistant.", messages=msgs, model=model,
                max_tokens=req.max_tokens or 2048, temperature=req.temperature, think=False)
    created, cid, t0 = int(time.time()), "chatcmpl-" + db.nid(), time.time()
    jid = activity.new_job("ide", last_user[:80] or "completion", model=model, mode=r["mode"])

    if req.stream:
        async def gen():
            head = {"id": cid, "object": "chat.completion.chunk", "created": created, "model": model,
                    "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}]}
            yield f"data: {json.dumps(head)}\n\n"
            out, status_, err = [], "ok", None
            activity.emit(jid, "generate", f"{model} · IDE")
            try:
                async for tok in adapter.run(greq):
                    out.append(tok)
                    chunk = {"id": cid, "object": "chat.completion.chunk", "created": created, "model": model,
                             "choices": [{"index": 0, "delta": {"content": tok}, "finish_reason": None}]}
                    yield f"data: {json.dumps(chunk)}\n\n"
            except Exception as e:
                status_, err = "error", str(e)
            tail = {"id": cid, "object": "chat.completion.chunk", "created": created, "model": model,
                    "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}
            yield f"data: {json.dumps(tail)}\n\n"
            yield "data: [DONE]\n\n"
            db.log_run(provider=r["provider"] or "local", model=model, capability="ide", conversation_id="ide",
                       context_ids_json="[]", in_tok=db.est_tokens(last_user), out_tok=db.est_tokens("".join(out)),
                       cost_est=providers.estimate_cost(model, db.est_tokens(last_user), db.est_tokens("".join(out))),
                       ms=int((time.time() - t0) * 1000), status=status_, error=err)
            activity.end_job(jid, ok=status_ == "ok")
        return StreamingResponse(gen(), media_type="text/event-stream")

    # non-streaming
    out = []
    try:
        async for tok in adapter.run(greq):
            out.append(tok)
    except Exception as e:
        activity.end_job(jid, ok=False, msg=str(e))
        raise HTTPException(502, str(e))
    text = "".join(out)
    it, ot = db.est_tokens(last_user), db.est_tokens(text)
    db.log_run(provider=r["provider"] or "local", model=model, capability="ide", conversation_id="ide",
               context_ids_json="[]", in_tok=it, out_tok=ot, cost_est=providers.estimate_cost(model, it, ot),
               ms=int((time.time() - t0) * 1000), status="ok", error=None)
    activity.end_job(jid, ok=True, msg=f"{ot} tokens")
    return {"id": cid, "object": "chat.completion", "created": created, "model": model,
            "choices": [{"index": 0, "message": {"role": "assistant", "content": text}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": it, "completion_tokens": ot, "total_tokens": it + ot}}

# ── OpenAI Responses API (for Codex CLI 0.155+, which dropped chat wire_api) ──
def _responses_extract(body: dict) -> tuple[str, list, str]:
    """Parse a Responses request → (system, messages, last_user_text)."""
    system = body.get("instructions") or ""
    inp = body.get("input", [])
    msgs, last_user = [], ""
    if isinstance(inp, str):
        msgs.append({"role": "user", "content": inp}); last_user = inp
        return system, msgs, last_user
    for item in inp:
        if not isinstance(item, dict):
            continue
        if item.get("type") in (None, "message"):
            role = item.get("role", "user")
            content = item.get("content", "")
            if isinstance(content, list):
                text = " ".join(p.get("text", "") for p in content
                                if isinstance(p, dict) and p.get("type") in ("input_text", "output_text", "text"))
            else:
                text = content
            if role in ("system", "developer"):
                system = (system + "\n" + text).strip() if system else text
            else:
                msgs.append({"role": "assistant" if role == "assistant" else "user", "content": text})
                if role == "user":
                    last_user = text
    return system, msgs, last_user

@app.post("/v1/responses")
async def oai_responses(body: dict):
    system, msgs, last_user = _responses_extract(body)
    r = resolve(body.get("model", "auto"), last_user, LOCAL._loaded if LOCAL else None)
    model = r["model"]
    adapter = providers.adapter_for(model) if model else None
    if not adapter or not model:
        raise HTTPException(503, f"no usable model ({r.get('reason', 'none')})")
    minfo = next((m for m in registry(False) if m["id"] == model), {})
    cloud = r["mode"] == "CLOUD"
    if cloud and not minfo.get("available"):
        raise HTTPException(503, f"'{model}' unavailable: {minfo.get('note')}")
    try:
        gate.check(adapter, "codex", providers.estimate_cost(model, db.est_tokens(last_user), 2048),
                   cloud=cloud, free=bool(minfo.get("free")))
    except gate.BudgetDenied as e:
        raise HTTPException(402, str(e))

    greq = GReq(system=system or "You are a precise coding assistant.", messages=msgs, model=model,
                max_tokens=body.get("max_output_tokens") or 2048, temperature=body.get("temperature", 0.4), think=False)
    rid, created, t0 = "resp_" + db.nid(), int(time.time()), time.time()
    stream = body.get("stream", False)
    jid = activity.new_job("codex", last_user[:80] or "responses", model=model, mode=r["mode"])

    if stream:
        async def gen():
            def ev(t, d): return f"event: {t}\ndata: {json.dumps({'type': t, **d})}\n\n"
            base_resp = {"id": rid, "object": "response", "created_at": created, "model": model, "status": "in_progress"}
            yield ev("response.created", {"response": base_resp})
            yield ev("response.output_item.added", {"output_index": 0,
                     "item": {"id": "msg_0", "type": "message", "role": "assistant", "content": []}})
            yield ev("response.content_part.added", {"item_id": "msg_0", "output_index": 0, "content_index": 0,
                     "part": {"type": "output_text", "text": ""}})
            out, err = [], None
            activity.emit(jid, "generate", f"{model} · Codex")
            try:
                async for tok in adapter.run(greq):
                    out.append(tok)
                    yield ev("response.output_text.delta", {"item_id": "msg_0", "output_index": 0, "content_index": 0, "delta": tok})
            except Exception as e:
                err = str(e)
            full = "".join(out)
            yield ev("response.output_text.done", {"item_id": "msg_0", "output_index": 0, "content_index": 0, "text": full})
            item = {"id": "msg_0", "type": "message", "role": "assistant",
                    "content": [{"type": "output_text", "text": full}]}
            yield ev("response.output_item.done", {"output_index": 0, "item": item})
            it, ot = db.est_tokens(last_user), db.est_tokens(full)
            done_resp = {**base_resp, "status": "completed" if not err else "failed", "output": [item],
                         "usage": {"input_tokens": it, "output_tokens": ot, "total_tokens": it + ot}}
            yield ev("response.completed", {"response": done_resp})
            db.log_run(provider=r["provider"] or "local", model=model, capability="codex", conversation_id="codex",
                       context_ids_json="[]", in_tok=it, out_tok=ot,
                       cost_est=providers.estimate_cost(model, it, ot), ms=int((time.time() - t0) * 1000),
                       status="ok" if not err else "error", error=err)
            activity.end_job(jid, ok=not err)
        return StreamingResponse(gen(), media_type="text/event-stream")

    out = []
    try:
        async for tok in adapter.run(greq):
            out.append(tok)
    except Exception as e:
        activity.end_job(jid, ok=False, msg=str(e)); raise HTTPException(502, str(e))
    text = "".join(out)
    it, ot = db.est_tokens(last_user), db.est_tokens(text)
    db.log_run(provider=r["provider"] or "local", model=model, capability="codex", conversation_id="codex",
               context_ids_json="[]", in_tok=it, out_tok=ot, cost_est=providers.estimate_cost(model, it, ot),
               ms=int((time.time() - t0) * 1000), status="ok", error=None)
    activity.end_job(jid, ok=True, msg=f"{ot} tokens")
    return {"id": rid, "object": "response", "created_at": created, "model": model, "status": "completed",
            "output": [{"id": "msg_0", "type": "message", "role": "assistant",
                        "content": [{"type": "output_text", "text": text}]}],
            "usage": {"input_tokens": it, "output_tokens": ot, "total_tokens": it + ot}}

# ── RAG (retrieval-augmented) ───────────────────────────────────────────
class RagIngest(BaseModel):
    path: str
    project_id: str | None = None
    tag: str = "rag"
    embed: bool = True

class RagQuery(BaseModel):
    q: str
    k: int = 5
    project_id: str | None = None

@app.post("/api/rag/add")
def rag_add(req: RagIngest):
    try:
        return rag.ingest_path(req.path, req.project_id, req.tag, req.embed)
    except FileNotFoundError:
        raise HTTPException(404, f"not found: {req.path}")
    except Exception as e:
        raise HTTPException(500, f"ingest failed: {e}")

@app.post("/api/rag/query")
def rag_query(req: RagQuery):
    return {"hits": rag.query(req.q, req.k, req.project_id)}

@app.get("/api/rag/stats")
def rag_stats():
    return rag.stats()

@app.post("/api/rag/embed")
def rag_embed_now():
    return rag.embed_pending()

# ── memory control ──────────────────────────────────────────────────────
class ForgetReq(BaseModel):
    scope: str = "conversations"      # conversations | all

@app.post("/api/memory/forget")
def memory_forget(req: ForgetReq):
    """Delete remembered content; settings, grants, audit and ledger are kept."""
    try:
        return db.forget(req.scope)
    except ValueError as e:
        raise HTTPException(400, str(e))

# ── serve UI ────────────────────────────────────────────────────────────
@app.get("/")
def root():
    if UI_FILE.exists():
        return FileResponse(UI_FILE)
    return {"status": "AIOS running"}
