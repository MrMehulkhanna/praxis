"""
Retrieval-augmented generation over the local context store.

Ingests markdown / text / PDF files into `objects` + `chunks`, keeps FTS5 in
sync (via the schema's `chunks_fts` external-content table), and — when an
embedder is loaded — writes 384-dim vectors into the `vectors` vec0 table.

Query returns the top-k chunks ranked by BM25 (FTS5) always; if embeddings
are present the vec0 cosine distance is fused in with a simple weighted score.
"""
from __future__ import annotations
import hashlib
import json
import pathlib
import re
import time
import uuid
from typing import Iterable, Optional

from core.store import db

# ---------------------------------------------------------------------------
# Chunking

_HDR = re.compile(r"^(#{1,6}\s|.+\n[=-]{3,}$)", re.MULTILINE)
_PARA = re.compile(r"\n\s*\n")


def chunk_text(text: str, target: int = 800, overlap: int = 120) -> list[str]:
    """Paragraph-first chunker with a target size in characters.

    - Respects blank-line paragraph boundaries.
    - If a paragraph is larger than 2× target, hard-wraps it with `overlap`
      characters carried between wraps so context isn't lost at the seam.
    """
    text = text.replace("\r\n", "\n").strip()
    if not text:
        return []
    paras = [p.strip() for p in _PARA.split(text) if p.strip()]

    chunks: list[str] = []
    cur = ""
    for p in paras:
        if len(p) > 2 * target:
            # flush current
            if cur:
                chunks.append(cur)
                cur = ""
            for i in range(0, len(p), target - overlap):
                chunks.append(p[i : i + target])
            continue
        if not cur:
            cur = p
        elif len(cur) + 1 + len(p) <= target:
            cur += "\n\n" + p
        else:
            chunks.append(cur)
            cur = p
    if cur:
        chunks.append(cur)
    return chunks


# ---------------------------------------------------------------------------
# File loaders

def _read_pdf(path: pathlib.Path) -> str:
    """PDF text extraction via pypdf if available; otherwise raises."""
    try:
        from pypdf import PdfReader  # type: ignore
    except ImportError as e:
        raise RuntimeError(
            "PDF ingestion needs pypdf — install with:\n"
            "  ~/aios/.venv/bin/pip install pypdf"
        ) from e
    r = PdfReader(str(path))
    return "\n\n".join(page.extract_text() or "" for page in r.pages)


def load_file(path: pathlib.Path) -> tuple[str, str]:
    """Return (title, body). Handles md/txt/rst/log/pdf."""
    ext = path.suffix.lower()
    if ext == ".pdf":
        return path.stem, _read_pdf(path)
    if ext in {".md", ".txt", ".rst", ".log", ".text", ".markdown", ""}:
        body = path.read_text(errors="replace")
        # first non-empty line as title (strip leading '# ')
        first = next((ln.strip() for ln in body.splitlines() if ln.strip()), path.stem)
        title = re.sub(r"^#+\s*", "", first)[:120]
        return title, body
    # anything else: try as text
    return path.stem, path.read_text(errors="replace")


# ---------------------------------------------------------------------------
# Ingest

def ingest_path(
    path: str | pathlib.Path,
    project_id: Optional[str] = None,
    tag: str = "rag",
    embed: bool = True,
) -> dict:
    """Ingest a file or directory. Returns a summary dict."""
    p = pathlib.Path(path).expanduser().resolve()
    if not p.exists():
        raise FileNotFoundError(p)

    files: list[pathlib.Path]
    if p.is_dir():
        files = [f for f in p.rglob("*") if f.is_file() and f.suffix.lower() in
                 {".md", ".txt", ".rst", ".log", ".markdown", ".pdf"}]
    else:
        files = [p]

    total_chunks = 0
    total_files = 0
    skipped: list[str] = []
    c = db.conn()

    for f in files:
        try:
            title, body = load_file(f)
        except Exception as e:
            skipped.append(f"{f}: {e}")
            continue
        if not body.strip():
            skipped.append(f"{f}: empty")
            continue

        content_hash = hashlib.sha256(body.encode()).hexdigest()
        # Skip if an object with the same source path + hash already exists
        existing = c.execute(
            "SELECT id FROM objects WHERE kind = 'document' "
            "AND CASE WHEN json_valid(meta_json) THEN json_extract(meta_json, '$.source') END = ? "
            "AND content_hash = ?",
            (str(f), content_hash),
        ).fetchone()
        if existing:
            skipped.append(f"{f}: already indexed")
            continue

        obj_id = str(uuid.uuid4())
        now = time.time()
        c.execute(
            "INSERT INTO objects (id, kind, project_id, title, body, meta_json, "
            "scope, importance, content_hash, created_at) VALUES "
            "(?, 'document', ?, ?, ?, ?, 'longterm', 0.6, ?, ?)",
            (obj_id, project_id, title, body,
             json.dumps({"source": str(f), "tag": tag}),
             content_hash, now),
        )
        chunks = chunk_text(body)
        # The chunks_ai trigger (schema.sql) indexes each row into chunks_fts
        # as it is inserted, so no FTS rebuild is needed here.
        c.executemany(
            "INSERT INTO chunks (object_id, ord, text, tokens) VALUES (?, ?, ?, ?)",
            [(obj_id, i, ch, max(1, len(ch) // 4)) for i, ch in enumerate(chunks)],
        )
        total_files += 1
        total_chunks += len(chunks)

    c.commit()

    if embed:
        try:
            embed_pending()
        except Exception as e:
            skipped.append(f"embedding step: {e}")

    return {
        "files": total_files,
        "chunks": total_chunks,
        "skipped": skipped[:10],
        "skipped_count": len(skipped),
    }


# ---------------------------------------------------------------------------
# Embedding — best-effort. Uses onnxruntime + a small all-MiniLM model if
# present in ~/aios/models/embed. Absent → skipped (BM25 still works).

_EMBED = None
_EMBED_DIM = 384


def _get_embedder():
    global _EMBED
    if _EMBED is not None:
        return _EMBED

    import os, pathlib
    home = pathlib.Path(os.environ.get("AIOS_HOME", pathlib.Path.home() / "aios"))
    model_dir = home / "models" / "embed"
    onnx = next(iter(model_dir.glob("*.onnx")), None) if model_dir.exists() else None
    if not onnx:
        return None

    try:
        import onnxruntime as ort  # type: ignore
        from tokenizers import Tokenizer  # type: ignore
    except ImportError:
        return None

    tok_path = model_dir / "tokenizer.json"
    if not tok_path.exists():
        return None
    tok = Tokenizer.from_file(str(tok_path))
    sess = ort.InferenceSession(str(onnx), providers=["CPUExecutionProvider"])
    _EMBED = (sess, tok)
    return _EMBED


def _embed_batch(texts: list[str]) -> Optional[list[list[float]]]:
    e = _get_embedder()
    if not e:
        return None
    sess, tok = e
    import numpy as np  # local import; numpy is in the AIOS venv
    encs = tok.encode_batch(texts)
    max_len = max(len(x.ids) for x in encs)
    ids = np.zeros((len(encs), max_len), dtype=np.int64)
    mask = np.zeros((len(encs), max_len), dtype=np.int64)
    for i, e_ in enumerate(encs):
        ids[i, :len(e_.ids)] = e_.ids
        mask[i, :len(e_.ids)] = 1
    out = sess.run(None, {"input_ids": ids, "attention_mask": mask})[0]
    # Mean-pool last hidden state weighted by attention mask
    m = mask[..., None].astype("float32")
    pooled = (out * m).sum(axis=1) / np.maximum(m.sum(axis=1), 1)
    # L2 normalise so cosine == dot
    pooled = pooled / np.maximum(np.linalg.norm(pooled, axis=1, keepdims=True), 1e-9)
    return pooled.astype("float32").tolist()


def embed_pending(batch: int = 32) -> dict:
    """Embed chunks where embedded=0."""
    c = db.conn()
    rows = c.execute(
        "SELECT id, text FROM chunks WHERE embedded = 0 ORDER BY id LIMIT 5000"
    ).fetchall()
    if not rows:
        return {"embedded": 0, "reason": "nothing pending"}
    if not _get_embedder():
        return {"embedded": 0, "reason": "no embedder installed (BM25 search still works)"}

    done = 0
    for i in range(0, len(rows), batch):
        block = rows[i : i + batch]
        vecs = _embed_batch([r["text"] for r in block])
        if not vecs:
            break
        for row, v in zip(block, vecs):
            c.execute(
                "INSERT OR REPLACE INTO vectors (chunk_id, emb) VALUES (?, ?)",
                (row["id"], _pack_vec(v)),
            )
            c.execute("UPDATE chunks SET embedded = 1 WHERE id = ?", (row["id"],))
            done += 1
        c.commit()
    return {"embedded": done}


def _pack_vec(v: list[float]) -> bytes:
    import struct
    return struct.pack(f"{len(v)}f", *v)


# ---------------------------------------------------------------------------
# Query

def query(
    q: str,
    k: int = 5,
    project_id: Optional[str] = None,
) -> list[dict]:
    """Return the top-k matching chunks.

    Always returns FTS5/BM25 results; if the vector table has entries and an
    embedder is available, fuses in vec0 cosine similarity via reciprocal-rank
    fusion (RRF).
    """
    q = q.strip()
    if not q:
        return []

    c = db.conn()

    # 1. BM25 / FTS5
    fts_rows = c.execute(
        """
        SELECT chunks.id AS chunk_id, chunks.object_id, chunks.text,
               objects.title, objects.meta_json,
               bm25(chunks_fts) AS score
        FROM chunks_fts
        JOIN chunks  ON chunks.id = chunks_fts.rowid
        JOIN objects ON objects.id = chunks.object_id
        WHERE chunks_fts MATCH ?
        ORDER BY score          -- BM25: lower is better
        LIMIT ?
        """,
        (_fts_escape(q), k * 5),
    ).fetchall()

    # 2. Vector similarity (only if embedder AND vectors both exist)
    vec_rows: list[dict] = []
    n_vec = c.execute("SELECT COUNT(*) FROM vectors").fetchone()[0]
    if n_vec and _get_embedder():
        qv = _embed_batch([q])
        if qv:
            packed = _pack_vec(qv[0])
            vec_rows = c.execute(
                """
                SELECT chunks.id AS chunk_id, chunks.object_id, chunks.text,
                       objects.title, objects.meta_json,
                       distance AS score
                FROM (
                    SELECT chunk_id, distance FROM vectors
                    WHERE emb MATCH ? AND k = ?
                ) v
                JOIN chunks  ON chunks.id = v.chunk_id
                JOIN objects ON objects.id = chunks.object_id
                ORDER BY score
                """,
                (packed, k * 5),
            ).fetchall()

    # 3. RRF fusion — rank-based, so the two score scales don't matter
    ranks: dict[int, float] = {}
    def add(rows: Iterable, weight: float):
        for i, r in enumerate(rows):
            ranks[r["chunk_id"]] = ranks.get(r["chunk_id"], 0.0) + weight / (60 + i)
    add(fts_rows, 1.0)
    add(vec_rows, 1.0 if vec_rows else 0.0)

    lookup = {r["chunk_id"]: r for r in list(fts_rows) + list(vec_rows)}
    top = sorted(ranks.items(), key=lambda x: -x[1])[:k]
    return [
        {
            "chunk_id": cid,
            "object_id": lookup[cid]["object_id"],
            "title": lookup[cid]["title"],
            "text": lookup[cid]["text"],
            "meta": lookup[cid]["meta_json"],
            "score": s,
        }
        for cid, s in top
    ]


def _fts_escape(q: str) -> str:
    """FTS5 MATCH-safe query: quote each word, join with OR."""
    words = re.findall(r"\w+", q)
    if not words:
        return q
    return " OR ".join(f'"{w}"' for w in words)


# ---------------------------------------------------------------------------
# Stats

def stats() -> dict:
    c = db.conn()
    r = {
        "documents": c.execute(
            "SELECT COUNT(*) FROM objects WHERE kind='document'"
        ).fetchone()[0],
        "chunks": c.execute("SELECT COUNT(*) FROM chunks").fetchone()[0],
        "embedded": c.execute(
            "SELECT COUNT(*) FROM chunks WHERE embedded=1"
        ).fetchone()[0],
        "vectors": c.execute("SELECT COUNT(*) FROM vectors").fetchone()[0],
        "embedder": bool(_get_embedder()),
    }
    return r
