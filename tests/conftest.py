"""Shared fixtures.

Every test runs against a throwaway AIOS_HOME, so the suite can never touch a
real ~/aios/aios.db. AIOS_HOME must be set before core.store.db is imported,
because db.py resolves DB_PATH at import time.
"""
import os
import pathlib
import sys
import tempfile

_TMP_HOME = tempfile.mkdtemp(prefix="aios-test-")
os.environ["AIOS_HOME"] = _TMP_HOME
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "src"))

import pytest  # noqa: E402

from core.store import db  # noqa: E402


@pytest.fixture(autouse=True)
def fresh_db():
    """Give each test an empty database file."""
    old = getattr(db._local, "db", None)
    if old is not None:
        old.close()
    db._local.db = None
    for suffix in ("", "-wal", "-shm"):
        p = pathlib.Path(str(db.DB_PATH) + suffix)
        if p.exists():
            p.unlink()
    yield db
    conn = getattr(db._local, "db", None)
    if conn is not None:
        conn.close()
    db._local.db = None
