"""
Provider manager: local llama-server + any number of OpenAI-compatible
cloud providers from config/providers.json. Owns the merged model registry.
"""
import json, os, pathlib, socket
from adapters.openai_compat import OpenAICompatAdapter, ProviderState

HOME = pathlib.Path(os.environ.get("AIOS_HOME", pathlib.Path.home() / "aios"))
CFG  = HOME / "config" / "providers.json"

_cloud: dict[str, OpenAICompatAdapter] = {}
_local = None

def init(local_adapter):
    global _local
    _local = local_adapter
    reload()

def reload():
    _cloud.clear()
    try:
        cfg = json.loads(CFG.read_text())
    except (OSError, ValueError):
        return
    for p in cfg.get("providers", []):
        try:
            _cloud[p["id"]] = OpenAICompatAdapter(p)
        except KeyError:
            continue

def online() -> bool:
    """Cheap connectivity probe (DNS + TCP), cached by callers per request."""
    try:
        socket.create_connection(("1.1.1.1", 443), timeout=1.5).close()
        return True
    except OSError:
        return False

def adapter_for(model_id: str):
    if model_id.startswith("local-"):
        return _local
    pid = model_id.split("/", 1)[0]
    return _cloud.get(pid)

def registry(local_models: list[dict], is_online: bool | None = None) -> list[dict]:
    """Merged model list. Cloud ids are '<provider>/<model>'."""
    out = list(local_models)
    net = online() if is_online is None else is_online
    for pid, a in _cloud.items():
        st = a.status()
        for m in a.models:
            available = st == ProviderState.OK and net
            out.append({
                "id": f"{pid}/{m['id']}", "provider": pid, "provider_name": a.name,
                "paid": not m.get("free", False), "free": bool(m.get("free", False)),
                "label": m.get("label", m["id"]), "role": m.get("role", "Daily"),
                "quality": m.get("quality", 3), "speed": m.get("speed", "fast"),
                "vram": "0", "ram": "0", "ctx": m.get("ctx", 8192),
                "cost_in": m.get("cost_in", 0), "cost_out": m.get("cost_out", 0),
                "note": (f"{a.name} · " + ("free tier" if m.get("free") else f"${m.get('cost_in',0)}/M in · ${m.get('cost_out',0)}/M out")
                         + ("" if available else f" · {st}" + (" (no internet)" if not net and st == ProviderState.OK else ""))),
                "available": available, "state": st,
            })
    return out

def status_list() -> list[dict]:
    net = online()
    rows = []
    for pid, a in _cloud.items():
        rows.append({
            "id": pid, "name": a.name, "enabled": a.enabled, "configured": bool(a.api_key) if a.key_env else True,
            "state": a.status() if net else ("offline" if a.enabled else a.status()),
            "reason": a.state_reason, "key_env": a.key_env, "paid": a.paid,
            "models": [m["id"] for m in a.models], "requests": a.requests, "failures": a.failures,
            "last_latency_ms": a.last_latency_ms, "quota": "unknown",
        })
    return rows

def estimate_cost(model_id: str, in_tok: int, out_tok: int) -> float:
    a = adapter_for(model_id)
    if not isinstance(a, OpenAICompatAdapter):
        return 0.0
    mid = model_id.split("/", 1)[1]
    m = next((x for x in a.models if x["id"] == mid), None)
    if not m or m.get("free"):
        return 0.0
    return round(in_tok / 1e6 * m.get("cost_in", 0) + out_tok / 1e6 * m.get("cost_out", 0), 6)
