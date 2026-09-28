"""Retrieval (RAG) and memory-control behaviour of the context store."""
import pytest

from core import rag
from core.store import db


# ── chunking ────────────────────────────────────────────────────────────────

def test_chunker_keeps_short_paragraphs_together():
    text = "alpha one.\n\nbeta two.\n\ngamma three."
    assert rag.chunk_text(text, target=800) == ["alpha one.\n\nbeta two.\n\ngamma three."]


def test_chunker_splits_at_paragraph_boundaries_when_over_target():
    paras = ["x" * 300, "y" * 300, "z" * 300]
    chunks = rag.chunk_text("\n\n".join(paras), target=700)
    assert len(chunks) == 2
    assert chunks[0] == paras[0] + "\n\n" + paras[1]
    assert chunks[1] == paras[2]


def test_chunker_hard_wraps_huge_paragraph_with_overlap():
    big = "".join(chr(ord("a") + i % 26) for i in range(3000))
    chunks = rag.chunk_text(big, target=800, overlap=100)
    assert all(len(c) <= 800 for c in chunks)
    # consecutive windows share `overlap` characters, so nothing is lost at a seam
    assert chunks[0][-100:] == chunks[1][:100]
    assert "".join(c[:700] for c in chunks[:-1]) + chunks[-1] == big


def test_chunker_empty_input():
    assert rag.chunk_text("   \n\n  ") == []


# ── ingest + query ──────────────────────────────────────────────────────────

def _write(tmp_path, name, text):
    p = tmp_path / name
    p.write_text(text)
    return p


def test_ingest_then_query_finds_the_document(tmp_path):
    doc = _write(tmp_path, "installer_notes.md",
                 "# Installer\n\nThe installer detects unallocated space and keeps Windows intact.")
    _write(tmp_path, "cooking.md", "# Pasta\n\nBoil water, add salt, cook for nine minutes.")
    summary = rag.ingest_path(tmp_path, embed=False)
    assert summary["files"] == 2
    hits = rag.query("unallocated space windows", k=3)
    assert hits and hits[0]["title"] == "Installer"
    assert str(doc) in hits[0]["meta"]


def test_reingesting_unchanged_file_is_skipped(tmp_path):
    _write(tmp_path, "a.md", "same content")
    assert rag.ingest_path(tmp_path, embed=False)["files"] == 1
    again = rag.ingest_path(tmp_path, embed=False)
    assert again["files"] == 0
    assert any("already indexed" in s for s in again["skipped"])


def test_paths_with_quotes_and_underscores_are_stored_safely(tmp_path):
    # `_` is a LIKE wildcard and `"` breaks hand-built JSON; both must be exact.
    lookalike = _write(tmp_path, 'myX"quoted"Xnotes.md', "hyprland quickshell praxis")
    weird = _write(tmp_path, 'my_"quoted"_notes.md', "hyprland quickshell praxis")
    assert rag.ingest_path(lookalike, embed=False)["files"] == 1
    # Same content, different path: must NOT be treated as already indexed.
    # (A LIKE pattern built from this path would let each `_` match the `X`.)
    assert rag.ingest_path(weird, embed=False)["files"] == 1


def test_query_on_empty_store_returns_nothing():
    assert rag.query("anything") == []
    assert rag.query("   ") == []


# ── forget ──────────────────────────────────────────────────────────────────

def _fts_rows():
    return db.conn().execute("SELECT COUNT(*) FROM chunks_fts WHERE chunks_fts MATCH 'praxis'").fetchone()[0]


def test_forget_conversations_keeps_documents(tmp_path):
    _write(tmp_path, "doc.md", "praxis documentation that must survive")
    rag.ingest_path(tmp_path, embed=False)
    db.add_object("message", "praxis chat message to forget", conversation_id="c1", role="user")

    result = db.forget("conversations")

    assert result["objects"] == 1
    kinds = [r[0] for r in db.conn().execute("SELECT kind FROM objects")]
    assert kinds == ["document"]
    assert _fts_rows() == 1          # the trigger removed the chat chunk from FTS


def test_forget_all_leaves_no_dangling_index_rows(tmp_path):
    _write(tmp_path, "doc.md", "praxis one")
    rag.ingest_path(tmp_path, embed=False)
    db.add_object("message", "praxis two", conversation_id="c1", role="user")

    db.forget("all")

    c = db.conn()
    assert c.execute("SELECT COUNT(*) FROM objects").fetchone()[0] == 0
    assert c.execute("SELECT COUNT(*) FROM chunks").fetchone()[0] == 0
    assert _fts_rows() == 0
    assert rag.query("praxis") == []


def test_forget_keeps_settings_and_ledger():
    db.kv_set("selected_model", "local-qwen3-4b")
    db.log_run(provider="local", model="qwen3-4b", status="ok")
    db.add_object("message", "hello", conversation_id="c1", role="user")

    db.forget("all")

    assert db.kv_get("selected_model") == "local-qwen3-4b"
    assert db.conn().execute("SELECT COUNT(*) FROM runs").fetchone()[0] == 1


def test_forget_rejects_unknown_scope():
    with pytest.raises(ValueError):
        db.forget("everything")
