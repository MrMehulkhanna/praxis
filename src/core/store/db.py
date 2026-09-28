"""Central SQLite access. One connection, WAL mode, everything in one file."""
import sqlite3, os, time, uuid, hashlib, json, pathlib, threading

try:
    import sqlite_vec
    _HAS_VEC = True
except ImportError:
    _HAS_VEC = False

HOME = pathlib.Path(os.environ.get("AIOS_HOME", pathlib.Path.home() / "aios"))
DB_PATH = HOME / "aios.db"

_local = threading.local()

def conn() -> sqlite3.Connection:
    if not hasattr(_local, "db") or _local.db is None:
        c = sqlite3.connect(str(DB_PATH), check_same_thread=False, timeout=15)
        c.row_factory = sqlite3.Row
        if _HAS_VEC:
            c.enable_load_extension(True)
            sqlite_vec.load(c)
            c.enable_load_extension(False)
        schema = (pathlib.Path(__file__).parent / "schema.sql").read_text()
        c.executescript(schema)
        if _HAS_VEC:
            c.execute(
                "CREATE VIRTUAL TABLE IF NOT EXISTS vectors "
                "USING vec0(chunk_id INTEGER PRIMARY KEY, emb float[384])"
            )
        c.commit()
        _local.db = c
    return _local.db

# ── helpers ────────────────────────────────────────────────────────────
def now() -> float:  return time.time()
def nid() -> str:    return uuid.uuid4().hex[:16]
def sha(s: str) -> str: return hashlib.sha256(s.encode()).hexdigest()
def est_tokens(s: str) -> int: return max(1, len(s) // 4)

CHUNK_SIZE = 1200   # characters per FTS/vector chunk

def add_object(
    kind: str,
    body: str,
    *,
    conversation_id: str | None = None,
    project_id: str | None = None,
    role: str | None = None,
    title: str | None = None,
    scope: str = "working",
    importance: float = 0.5,
    meta: dict | None = None,
) -> str:
    c = conn()
    oid = nid()
    body = body.strip()
    c.execute(
        "INSERT INTO objects "
        "(id,kind,project_id,conversation_id,role,title,body,"
        "meta_json,scope,importance,tokens_est,content_hash,created_at,last_used_at) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (oid, kind, project_id, conversation_id, role, title, body,
         json.dumps(meta or {}), scope, importance,
         est_tokens(body), sha(body), now(), now()),
    )
    # chunk into FTS
    for i in range(0, max(1, len(body)), CHUNK_SIZE):
        part = body[i : i + CHUNK_SIZE]
        c.execute(
            "INSERT INTO chunks (object_id,ord,text,tokens) VALUES (?,?,?,?)",
            (oid, i // CHUNK_SIZE, part, est_tokens(part)),
        )
    c.commit()
    return oid

def update_use(object_id: str):
    conn().execute(
        "UPDATE objects SET use_count=use_count+1, last_used_at=? WHERE id=?",
        (now(), object_id),
    )
    conn().commit()

def link(src: str, dst: str, rel: str, weight: float = 1.0):
    conn().execute(
        "INSERT OR REPLACE INTO edges VALUES (?,?,?,?)", (src, dst, rel, weight)
    )
    conn().commit()

def recent_messages(conversation_id: str, limit: int = 10) -> list:
    rows = conn().execute(
        "SELECT * FROM objects WHERE conversation_id=? AND kind='message' "
        "ORDER BY created_at DESC LIMIT ?",
        (conversation_id, limit),
    ).fetchall()
    return list(reversed(rows))

def search_fts(query: str, k: int = 40, exclude_conv: str | None = None) -> list:
    # clean query for FTS5 — keep words only
    words = [
        w for w in
        "".join(ch if ch.isalnum() or ch.isspace() else " " for ch in query).split()
        if len(w) > 2
    ]
    if not words:
        return []
    fts_q = " OR ".join(words)
    sql = (
        "SELECT c.id, c.object_id, c.text, c.tokens, "
        "o.kind, o.created_at, o.importance, bm25(chunks_fts) AS bm25 "
        "FROM chunks_fts "
        "JOIN chunks c  ON c.id = chunks_fts.rowid "
        "JOIN objects o ON o.id = c.object_id "
        "WHERE chunks_fts MATCH ? "
    )
    args: list = [fts_q]
    if exclude_conv:
        sql += "AND (o.conversation_id IS NULL OR o.conversation_id != ?) "
        args.append(exclude_conv)
    sql += "ORDER BY bm25 LIMIT ?"
    args.append(k)
    try:
        return conn().execute(sql, args).fetchall()
    except sqlite3.OperationalError:
        return []

def log_run(**kw):
    kw.setdefault("id", nid())
    kw.setdefault("created_at", now())
    cols = ", ".join(kw)
    qs   = ", ".join("?" * len(kw))
    conn().execute(f"INSERT INTO runs ({cols}) VALUES ({qs})", tuple(kw.values()))
    conn().commit()

def kv_get(key: str, default=None):
    row = conn().execute("SELECT value FROM kv WHERE key=?", (key,)).fetchone()
    return json.loads(row["value"]) if row else default

def kv_set(key: str, value):
    conn().execute("INSERT OR REPLACE INTO kv VALUES (?,?)", (key, json.dumps(value)))
    conn().commit()

def db_stats() -> dict:
    c = conn()
    rows    = c.execute("SELECT COUNT(*) FROM objects").fetchone()[0]
    db_mb   = round(DB_PATH.stat().st_size / 1e6, 1) if DB_PATH.exists() else 0
    runs    = c.execute("SELECT COUNT(*) FROM runs").fetchone()[0]
    return {"objects": rows, "runs": runs, "db_mb": db_mb}

FORGET_SCOPES = ("conversations", "all")

def forget(scope: str = "conversations") -> dict:
    """Delete remembered content in one transaction.

    scope="conversations"  chat messages only (objects with a conversation_id)
    scope="all"            every stored object: chats, ingested documents, notes

    Deliberately kept: settings (kv), permission grants, the audit trail and
    the usage ledger (runs) — forgetting what was said must not erase what was
    allowed, what was done, or what it cost.

    Foreign keys are not enabled on this connection, so ON DELETE CASCADE does
    not fire: children are removed explicitly, vectors first. The chunks_ad
    trigger keeps the FTS index consistent as chunks are deleted.
    """
    if scope not in FORGET_SCOPES:
        raise ValueError(f"scope must be one of {FORGET_SCOPES}")
    where = "conversation_id IS NOT NULL" if scope == "conversations" else "1=1"
    c = conn()
    with c:
        c.execute("CREATE TEMP TABLE IF NOT EXISTS forget_ids (id TEXT PRIMARY KEY)")
        c.execute("DELETE FROM forget_ids")
        c.execute(f"INSERT INTO forget_ids SELECT id FROM objects WHERE {where}")
        chunk_ids = [r[0] for r in c.execute(
            "SELECT id FROM chunks WHERE object_id IN (SELECT id FROM forget_ids)")]
        if _HAS_VEC and chunk_ids:
            c.executemany("DELETE FROM vectors WHERE chunk_id = ?", [(i,) for i in chunk_ids])
        n_chunks = c.execute(
            "DELETE FROM chunks WHERE object_id IN (SELECT id FROM forget_ids)").rowcount
        n_edges = c.execute(
            "DELETE FROM edges WHERE src_id IN (SELECT id FROM forget_ids) "
            "OR dst_id IN (SELECT id FROM forget_ids)").rowcount
        n_objects = c.execute(
            "DELETE FROM objects WHERE id IN (SELECT id FROM forget_ids)").rowcount
        c.execute("DELETE FROM forget_ids")
    return {"scope": scope, "objects": n_objects, "chunks": n_chunks, "edges": n_edges}
