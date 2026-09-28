-- AIOS persistent store. One file, everything lives here.
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA temp_store=MEMORY;
PRAGMA mmap_size=268435456;   -- 256 MB window, not resident
PRAGMA cache_size=-32000;     -- 32 MB page cache

-- ── projects ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS projects (
  id   TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  path TEXT,                  -- local directory, if any
  description TEXT,
  meta_json TEXT DEFAULT '{}',
  created_at REAL,
  last_used_at REAL
);

-- ── one table for every addressable object ────────────────────────────
-- kind: message | memory | fact | decision | task | file | asset |
--       error | tool_result | code | summary | note
CREATE TABLE IF NOT EXISTS objects (
  id              TEXT PRIMARY KEY,
  kind            TEXT NOT NULL,
  project_id      TEXT REFERENCES projects(id),
  conversation_id TEXT,
  role            TEXT,       -- user | assistant | system | tool
  title           TEXT,
  body            TEXT NOT NULL DEFAULT '',
  meta_json       TEXT DEFAULT '{}',
  scope           TEXT DEFAULT 'working',   -- working|project|longterm|archive
  importance      REAL DEFAULT 0.5,         -- 0.0–1.0, updated by use
  tokens_est      INTEGER DEFAULT 0,
  content_hash    TEXT,
  created_at      REAL NOT NULL,
  last_used_at    REAL,
  use_count       INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ix_obj_conv  ON objects(conversation_id, created_at);
CREATE INDEX IF NOT EXISTS ix_obj_proj  ON objects(project_id, kind, created_at);
CREATE INDEX IF NOT EXISTS ix_obj_scope ON objects(scope, importance);
CREATE INDEX IF NOT EXISTS ix_obj_hash  ON objects(content_hash);

-- ── graph edges between objects ───────────────────────────────────────
-- rel: answers | derived_from | about | caused | fixes | part_of | cites | uses
CREATE TABLE IF NOT EXISTS edges (
  src_id  TEXT NOT NULL,
  dst_id  TEXT NOT NULL,
  rel     TEXT NOT NULL,
  weight  REAL DEFAULT 1.0,
  PRIMARY KEY (src_id, dst_id, rel)
);
CREATE INDEX IF NOT EXISTS ix_edge_dst ON edges(dst_id, rel);

-- ── text chunks for FTS and vector search ─────────────────────────────
CREATE TABLE IF NOT EXISTS chunks (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  object_id  TEXT NOT NULL REFERENCES objects(id) ON DELETE CASCADE,
  ord        INTEGER NOT NULL,
  text       TEXT NOT NULL,
  tokens     INTEGER DEFAULT 0,
  embedded   INTEGER DEFAULT 0   -- 0=not yet, 1=done
);
CREATE INDEX IF NOT EXISTS ix_chunk_obj ON chunks(object_id, ord);

-- FTS5 full-text index (porter stemmer + unicode folding)
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
  text,
  content='chunks',
  content_rowid='id',
  tokenize='porter unicode61'
);
CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
  INSERT INTO chunks_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
  INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.id, old.text);
END;
CREATE TRIGGER IF NOT EXISTS chunks_au AFTER UPDATE OF text ON chunks BEGIN
  INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.id, old.text);
  INSERT INTO chunks_fts(rowid, text) VALUES (new.id, new.text);
END;

-- ── raw file assets (deduped by sha256) ──────────────────────────────
CREATE TABLE IF NOT EXISTS assets (
  id         TEXT PRIMARY KEY,
  sha256     TEXT UNIQUE NOT NULL,
  blob_path  TEXT NOT NULL,    -- relative to $AIOS_HOME/blobs/
  mime       TEXT,
  bytes      INTEGER,
  width      INTEGER, height INTEGER, duration_s REAL,
  meta_json  TEXT DEFAULT '{}',
  created_at REAL
);

-- ── every model invocation ledger ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS runs (
  id               TEXT PRIMARY KEY,
  provider         TEXT NOT NULL,
  model            TEXT NOT NULL,
  capability       TEXT DEFAULT 'chat',
  conversation_id  TEXT,
  context_ids_json TEXT DEFAULT '[]',
  in_tok           INTEGER DEFAULT 0,
  out_tok          INTEGER DEFAULT 0,
  cost_est         REAL DEFAULT 0.0,
  ms               INTEGER,
  status           TEXT,       -- ok | error | denied | timeout | cancelled
  error            TEXT,
  created_at       REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_runs_conv ON runs(conversation_id, created_at);

-- ── permission grants ─────────────────────────────────────────────────
-- perm: READ | WRITE | EXECUTE | NETWORK | DELETE
CREATE TABLE IF NOT EXISTS grants (
  id          TEXT PRIMARY KEY,
  tool        TEXT NOT NULL,   -- fs | shell | git | python | browser
  scope_glob  TEXT NOT NULL,   -- e.g. ~/ros2_ws/**
  perm        TEXT NOT NULL,
  granted_at  REAL NOT NULL,
  expires_at  REAL            -- NULL = session only
);

-- ── audit trail ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  actor     TEXT,             -- user | model | system
  action    TEXT NOT NULL,
  args_hash TEXT,
  decision  TEXT,             -- allow | deny | prompt
  result    TEXT,
  at        REAL NOT NULL
);

-- ── key-value store for app state ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS kv (
  key   TEXT PRIMARY KEY,
  value TEXT
);
