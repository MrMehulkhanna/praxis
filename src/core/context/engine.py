"""
Retrieve → Rank → Dedup → Budget → STOP EARLY → Render

Stop-early is the key optimisation. Most questions need 400–1500 tokens
of context, not 100k. Filling the window slows inference and costs money.
"""
import time, math
from core.store import db

# ── scoring weights ────────────────────────────────────────────────────
W_BM25       = 0.45
W_RECENCY    = 0.25
W_IMPORTANCE = 0.30
MIN_SCORE    = 0.35     # chunks below this are ignored — raise to 0.45 if noisy

def _norm_bm25(raw: float) -> float:
    # sqlite FTS5 bm25() returns negative; less negative = more relevant
    return max(0.0, min(1.0, -raw / 12.0))

def _recency(ts: float, half_life_days: float = 7.0) -> float:
    age_days = (time.time() - ts) / 86400.0
    return math.pow(0.5, age_days / half_life_days)

def build(
    user_msg: str,
    conversation_id: str,
    *,
    ctx_window: int = 8192,
    project_id: str | None = None,
) -> dict:
    budget   = int(ctx_window * 0.50)   # hard cap: never fill the window
    hard_cap = int(ctx_window * 0.25)   # recent turns get at most 25%
    used     = 0
    ids: list[str] = []

    # ── 1. recent turns of this conversation (rolling window) ──────────
    turns: list[dict] = []
    for row in db.recent_messages(conversation_id, limit=10):
        t = row["tokens_est"]
        if used + t > hard_cap:
            break
        turns.append({"role": row["role"] or "user", "content": row["body"]})
        used += t
        ids.append(row["id"])

    # ── 2. FTS retrieval from global memory (excluding current conv) ───
    candidates: list[tuple[float, object]] = []
    for row in db.search_fts(user_msg, k=40, exclude_conv=conversation_id):
        score = (
            W_BM25       * _norm_bm25(row["bm25"])
            + W_RECENCY    * _recency(row["created_at"])
            + W_IMPORTANCE * row["importance"]
        )
        candidates.append((score, row))
    candidates.sort(key=lambda x: -x[0])

    # ── 3. fill retrieved context: rank, dedup, stop early ────────────
    retrieved: list[str] = []
    seen: set[int] = set()
    for score, row in candidates:
        if score < MIN_SCORE:
            break                                   # ← STOP EARLY here
        key = hash(row["text"][:300])
        if key in seen:
            continue                                # dedup
        tok = row["tokens"]
        if used + tok > budget:
            break
        seen.add(key)
        label = f"[{row['kind']}]"
        retrieved.append(f"{label} {row['text']}")
        used += tok
        ids.append(str(row["object_id"]))
        db.update_use(str(row["object_id"]))

    return {
        "turns":     turns,
        "retrieved": retrieved,
        "tokens":    used,
        "budget":    budget,
        "ids":       list(dict.fromkeys(ids)),   # preserve order, remove dupes
    }

def render_system(pkg: dict, model_name: str = "") -> str:
    base = (
        "You are AIOS, a local-first personal AI running entirely on the user's "
        "own machine. Be direct, concise, and honest. "
        "You have access to a persistent memory system across conversations."
    )
    if not pkg["retrieved"]:
        return base
    ctx = "\n\n<retrieved_context>\n"
    ctx += "\n---\n".join(pkg["retrieved"])
    ctx += "\n</retrieved_context>"
    return base + ctx
