import sqlite3
import time
from pathlib import Path
from typing import Optional

import models as m

SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at REAL NOT NULL,
    status TEXT NOT NULL,
    source TEXT NOT NULL,
    filename TEXT NOT NULL,
    blob_path TEXT NOT NULL,
    width_mm INTEGER NOT NULL DEFAULT 80,
    error TEXT,
    started_at REAL,
    finished_at REAL
);
CREATE INDEX IF NOT EXISTS jobs_status ON jobs(status);
"""


class Queue:
    def __init__(self, db_path: Path):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(self.db_path), check_same_thread=False, isolation_level=None)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.executescript(SCHEMA)
        # Lightweight migration for pre-width_mm DBs.
        cols = {r[1] for r in self._conn.execute("PRAGMA table_info(jobs)").fetchall()}
        if "width_mm" not in cols:
            self._conn.execute("ALTER TABLE jobs ADD COLUMN width_mm INTEGER NOT NULL DEFAULT 80")
        # Recover any jobs that were "printing" when we died.
        self._conn.execute("UPDATE jobs SET status='queued', started_at=NULL WHERE status='printing'")

    def enqueue(self, source: m.JobSource, filename: str, blob_path: str, width_mm: int = 80) -> int:
        cur = self._conn.execute(
            "INSERT INTO jobs(created_at, status, source, filename, blob_path, width_mm) VALUES (?, 'queued', ?, ?, ?, ?)",
            (time.time(), source, filename, blob_path, width_mm),
        )
        return cur.lastrowid

    def claim_next(self) -> Optional[m.Job]:
        row = self._conn.execute(
            """
            UPDATE jobs SET status='printing', started_at=?
            WHERE id = (SELECT id FROM jobs WHERE status='queued' ORDER BY id LIMIT 1)
            RETURNING *
            """,
            (time.time(),),
        ).fetchone()
        return _row_to_job(row) if row else None

    def complete(self, job_id: int) -> None:
        self._conn.execute(
            "UPDATE jobs SET status='done', finished_at=? WHERE id=?",
            (time.time(), job_id),
        )

    def fail(self, job_id: int, error: str) -> None:
        self._conn.execute(
            "UPDATE jobs SET status='failed', finished_at=?, error=? WHERE id=?",
            (time.time(), error, job_id),
        )

    def get(self, job_id: int) -> Optional[m.Job]:
        row = self._conn.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        return _row_to_job(row) if row else None

    def recent(self, limit: int = 100) -> list[m.Job]:
        rows = self._conn.execute(
            "SELECT * FROM jobs ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
        return [_row_to_job(r) for r in rows]

    def close(self) -> None:
        self._conn.close()


def _row_to_job(row: sqlite3.Row) -> m.Job:
    return m.Job(
        id=row["id"],
        created_at=row["created_at"],
        status=row["status"],
        source=row["source"],
        filename=row["filename"],
        blob_path=row["blob_path"],
        width_mm=row["width_mm"] if "width_mm" in row.keys() else 80,
        error=row["error"],
        started_at=row["started_at"],
        finished_at=row["finished_at"],
    )
