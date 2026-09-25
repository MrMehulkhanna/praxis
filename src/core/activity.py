"""
Activity bus — the "what is my computer doing" feed.

Every pipeline stage (request → classify → route → gather → generate →
approve → execute → analyse → result) emits an event here. Consumers:
the shell's Activity panel and `ai logs -f` (SSE), plus a plain-text log.
"""
import asyncio, collections, json, os, pathlib, time, uuid

HOME = pathlib.Path(os.environ.get("AIOS_HOME", pathlib.Path.home() / "aios"))
LOG  = HOME / "logs" / "activity.log"

_events: collections.deque = collections.deque(maxlen=600)
_subs: set[asyncio.Queue] = set()
jobs: dict[str, dict] = {}          # live jobs: id -> {kind, model, mode, stage, started, title}

def new_job(kind: str, title: str, model: str = "", mode: str = "") -> str:
    jid = uuid.uuid4().hex[:8]
    jobs[jid] = {"id": jid, "kind": kind, "title": title[:120], "model": model, "mode": mode,
                 "stage": "received", "started": time.time()}
    emit(jid, "received", f"{kind}: {title[:80]}")
    return jid

def update_job(jid: str, **kw):
    if jid in jobs:
        jobs[jid].update(kw)

def end_job(jid: str, ok: bool = True, msg: str = ""):
    j = jobs.pop(jid, None)
    if j:
        ms = int((time.time() - j["started"]) * 1000)
        emit(jid, "result" if ok else "error", msg or ("done in %d ms" % ms), ms=ms, model=j.get("model"), mode=j.get("mode"))

def emit(jid: str | None, stage: str, msg: str, **data):
    ev = {"ts": time.time(), "job": jid, "stage": stage, "msg": msg[:500], **data}
    if jid in jobs:
        jobs[jid]["stage"] = stage
    _events.append(ev)
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG, "a") as f:
            f.write(time.strftime("%H:%M:%S", time.localtime(ev["ts"])) + f" [{jid or '-'}] {stage:10} {msg}\n")
    except OSError:
        pass
    for q in list(_subs):
        try:
            q.put_nowait(ev)
        except asyncio.QueueFull:
            pass

def recent(limit: int = 100) -> list[dict]:
    return list(_events)[-limit:]

async def stream():
    """Async generator of SSE lines for one subscriber."""
    q: asyncio.Queue = asyncio.Queue(maxsize=200)
    _subs.add(q)
    try:
        yield f"event: jobs\ndata: {json.dumps(list(jobs.values()))}\n\n"
        while True:
            try:
                ev = await asyncio.wait_for(q.get(), timeout=15)
                yield f"data: {json.dumps(ev)}\n\n"
                if ev["stage"] in ("received", "result", "error"):
                    yield f"event: jobs\ndata: {json.dumps(list(jobs.values()))}\n\n"
            except asyncio.TimeoutError:
                yield ": keepalive\n\n"
    finally:
        _subs.discard(q)
