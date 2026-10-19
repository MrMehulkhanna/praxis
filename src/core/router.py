"""
Task classification + model routing.

classify() is pure heuristics — no model call, microseconds, works offline.
choose() picks the best *available* model for the task under the current
budget mode, with a strong preference for whatever is already loaded in
VRAM (a model swap on a 6 GB card costs 10–20 s).
"""
import re
from core.store import db

TASKS = ("code", "debug", "sysadmin", "reasoning", "general")

_PAT = {
    "debug": r"\b(error|traceback|exception|stack ?trace|segfault|crash(es|ed|ing)?|fail(s|ed|ing)?|not working|doesn'?t work|bug|broken|fix (this|my|the)|why (is|does|did|isn'?t|won'?t)|undefined|null ?pointer|panic|core dump|compil(e|ation) error|build (error|fail))\b",
    "sysadmin": r"\b(systemctl|journalctl|dmesg|kernel|driver|boot(ing|s)?|grub|pacman|yay|paru|arch ?linux|hyprland|wayland|pipewire|wpctl|nvidia|gpu (not|isn'?t)|vram|cuda|nmcli|wifi|bluetooth|mount|fstab|partition|disk|ssd|nvme|swap|service|daemon|permission denied|sudo|chmod|chown|ssh|firewall|port \d+|dns|ip addr|uptime|cpu|gpu|ram|memory|vram|temperature|temps?|battery|power profile|fan|thermal|throttl|processes|usage|storage|free space|hardware)\w*\b",
    "code": r"\b(code|function|class|method|script|refactor|implement|write (a|an|the|me)? ?(python|bash|rust|c\+\+|js|typescript|go|node|ros ?2?)|python|bash|rust|c\+\+|typescript|javascript|golang|ros ?2|node|api|regex|sql|json|yaml|dockerfile|docker|cmake|makefile|unit test|pytest|git (rebase|merge|bisect)|algorithm|data ?structure)\b",
    "reasoning": r"\b(explain|why|compare|analy[sz]e|design|architect|plan|trade-?offs?|pros and cons|strategy|evaluate|recommend|should i|what is the (best|difference)|step by step|in depth|deeply)\b",
}

def classify(text: str) -> dict:
    t = text.lower()
    scores = {k: len(re.findall(p, t)) for k, p in _PAT.items()}
    # code blocks / stack traces are strong signals
    if "```" in text or re.search(r"^\s*(File \"|at |Traceback)", text, re.M):
        scores["debug"] += 2
    if re.search(r"[{};]\s*$", text, re.M) or "def " in text or "#include" in text:
        scores["code"] += 2
    task = max(scores, key=lambda k: scores[k]) if any(scores.values()) else "general"
    if task == "debug" and scores["sysadmin"] >= scores["debug"]:
        task = "sysadmin"
    return {"task": task, "scores": scores, "tokens": max(1, len(text) // 4),
            "diagnostic": task in ("sysadmin", "debug") and scores["sysadmin"] > 0}

# quality tiers per task: which model roles fit (best first)
_PREF = {
    "code":      ["Code", "Quality", "Daily"],
    "debug":     ["Code", "Quality", "Daily"],
    "sysadmin":  ["Quality", "Daily", "Code"],
    "reasoning": ["Quality", "Daily", "Code"],
    "general":   ["Daily", "Quality", "Code"],
}

def choose(task: str, models: list[dict], loaded: str | None, budget_mode: str,
           online: bool, prefer_cloud_for: list[str] | None = None, tokens: int = 0,
           needs_vision: bool = False) -> dict:
    """models: output of the merged model registry (local + providers)."""
    avail = [m for m in models if m.get("available") and (not needs_vision or m.get("vision"))]
    if needs_vision and not avail:
        return {"model": None, "provider": None, "mode": "NONE", "reason": "no vision-capable model available (download Qwen3-VL)"}
    local = [m for m in avail if m["provider"] == "local"]
    cloud = [m for m in avail if m["provider"] != "local"]

    # 1. cloud only when allowed AND the user opted this task type in
    if cloud and online and budget_mode != "ZERO_COST" and budget_mode != "LOCAL_ONLY" \
            and task in (prefer_cloud_for or []):
        if budget_mode == "FREE_ONLINE":
            cloud = [m for m in cloud if m.get("free")]
        if cloud:
            best = max(cloud, key=lambda m: (m.get("quality", 0), m.get("ctx", 0)))
            return {"model": best["id"], "provider": best["provider"], "mode": "CLOUD",
                    "reason": f"{task} task · cloud allowed ({budget_mode}) · best quality available"}

    # 2. local: role preference, then stickiness to the loaded model
    if not local:
        return {"model": None, "provider": None, "mode": "NONE", "reason": "no local model downloaded"}
    prefs = _PREF.get(task, _PREF["general"])
    ranked = sorted(local, key=lambda m: (prefs.index(m["role"]) if m["role"] in prefs else 9, -m.get("quality", 0)))
    best = ranked[0]
    # long inputs need context room
    if tokens > 2500:
        big = max(local, key=lambda m: m.get("ctx", 0))
        if big["ctx"] > best["ctx"]:
            best = big
    # stickiness: keep the loaded model if it is within one tier of the best fit
    if loaded and loaded != best["id"]:
        cur = next((m for m in local if m["id"] == loaded), None)
        if cur and cur["role"] in prefs and prefs.index(cur["role"]) <= prefs.index(best["role"]) + 1 \
                and not (task in ("code", "debug") and best["role"] == "Code"):
            return {"model": cur["id"], "provider": "local", "mode": "LOCAL",
                    "reason": f"{task} task · {cur['label']} already loaded (avoids a model swap)"}
    return {"model": best["id"], "provider": "local", "mode": "LOCAL",
            "reason": f"{task} task → {best['role'].lower()} model" + (" · offline-safe" if not online else "")}

def prefer_cloud_for() -> list[str]:
    return db.kv_get("prefer_cloud_for", [])
