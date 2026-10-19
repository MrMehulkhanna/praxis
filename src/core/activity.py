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
    stop = _stops.pop(jid, None)
    if j:
        ms = int((time.time() - j["started"]) * 1000)
        if stop is not None and stop.is_set():
            emit(jid, "cancelled", f"stopped after {ms} ms", ms=ms, model=j.get("model"), mode=j.get("mode"))
        else:
            emit(jid, "result" if ok else "error", msg or ("done in %d ms" % ms), ms=ms, model=j.get("model"), mode=j.get("mode"))

# ── stopping a job ─────────────────────────────────────────────────────────
class Cancelled(Exception):
    """Raised inside a generation whose job was stopped."""

_stops: dict[str, asyncio.Event] = {}

def _stop_event(jid: str) -> asyncio.Event:
    ev = _stops.get(jid)
    if ev is None:
        ev = _stops[jid] = asyncio.Event()
    return ev

def cancel_job(jid: str) -> bool:
    """Ask a running job to stop. Call from the event loop (an async endpoint)."""
    if jid not in jobs:
        return False
    _stop_event(jid).set()
    emit(jid, "stopping", "stop requested")
    return True

def stopped(jid: str) -> bool:
    ev = _stops.get(jid)
    return ev is not None and ev.is_set()

async def guard(jid: str, tokens):
    """Relay a generation's tokens until its job is stopped.

    A stop cancels the pending read at once — even mid prompt-processing — which
    closes the stream to the model server (llama-server stops generating when
    its client goes away), then raises Cancelled for the caller to report.
    If the caller is itself cancelled (the HTTP client disconnected), the job is
    closed here, because the caller's own end_job() is never reached."""
    stop = _stop_event(jid)
    it = tokens.__aiter__()
    try:
        while True:
            nxt = asyncio.ensure_future(it.__anext__())
            waiter = asyncio.ensure_future(stop.wait())
            try:
                await asyncio.wait({nxt, waiter}, return_when=asyncio.FIRST_COMPLETED)
            finally:
                waiter.cancel()
                if not nxt.done():
                    nxt.cancel()
                    await asyncio.gather(nxt, return_exceptions=True)
            if stop.is_set():
                raise Cancelled("stopped by user")
            try:
                tok = nxt.result()
            except StopAsyncIteration:
                return
            yield tok
    except (asyncio.CancelledError, GeneratorExit):
        end_job(jid, ok=False, msg="client disconnected")
        raise
    finally:
        aclose = getattr(it, "aclose", None)
        if aclose is not None:
            try:
                await aclose()
            except Exception:
                pass

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
                if ev["stage"] in ("received", "result", "error", "stopping", "cancelled"):
                    yield f"event: jobs\ndata: {json.dumps(list(jobs.values()))}\n\n"
            except asyncio.TimeoutError:
                yield ": keepalive\n\n"
    finally:
        _subs.discard(q)
