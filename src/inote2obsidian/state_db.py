from __future__ import annotations

import sqlite3
import uuid
from contextlib import contextmanager
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

from inote2obsidian.models import AssetState, NoteState, RunContext, SyncStats


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class StateDB:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

    @contextmanager
    def connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    def init_schema(self) -> None:
        with self.connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS notes_state (
                  note_id TEXT PRIMARY KEY,
                  folder_name TEXT NOT NULL,
                  title TEXT,
                  source_updated_at TEXT NOT NULL,
                  content_hash TEXT NOT NULL,
                  md_rel_path TEXT NOT NULL,
                  is_deleted INTEGER NOT NULL DEFAULT 0,
                  last_synced_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS assets_state (
                  asset_id TEXT PRIMARY KEY,
                  note_id TEXT NOT NULL,
                  source_asset_ref TEXT NOT NULL,
                  asset_hash TEXT NOT NULL,
                  asset_rel_path TEXT NOT NULL,
                  last_synced_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS sync_runs (
                  run_id TEXT PRIMARY KEY,
                  started_at TEXT NOT NULL,
                  ended_at TEXT,
                  status TEXT NOT NULL,
                  added_count INTEGER DEFAULT 0,
                  updated_count INTEGER DEFAULT 0,
                  deleted_count INTEGER DEFAULT 0,
                  error_count INTEGER DEFAULT 0
                );
                """
            )

    def start_run(self) -> RunContext:
        run = RunContext(run_id=str(uuid.uuid4()), started_at=_now_iso())
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO sync_runs(run_id, started_at, status, added_count, updated_count, deleted_count, error_count)
                VALUES(?, ?, 'failed', 0, 0, 0, 0)
                """,
                (run.run_id, run.started_at),
            )
        return run

    def finish_run(self, run_id: str, status: str, stats: SyncStats) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                UPDATE sync_runs
                   SET ended_at = ?, status = ?, added_count = ?, updated_count = ?, deleted_count = ?, error_count = ?
                 WHERE run_id = ?
                """,
                (
                    _now_iso(),
                    status,
                    stats.added_count,
                    stats.updated_count,
                    stats.deleted_count,
                    stats.error_count,
                    run_id,
                ),
            )

    def get_last_run(self) -> sqlite3.Row | None:
        with self.connect() as conn:
            return conn.execute(
                "SELECT * FROM sync_runs ORDER BY started_at DESC LIMIT 1"
            ).fetchone()

    def get_note_state(self, note_id: str) -> NoteState | None:
        with self.connect() as conn:
            row = conn.execute(
                "SELECT * FROM notes_state WHERE note_id = ?", (note_id,)
            ).fetchone()
        if row is None:
            return None
        return NoteState(**dict(row))

    def upsert_note_state(self, state: NoteState) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO notes_state(note_id, folder_name, title, source_updated_at, content_hash, md_rel_path, is_deleted, last_synced_at)
                VALUES(:note_id, :folder_name, :title, :source_updated_at, :content_hash, :md_rel_path, :is_deleted, :last_synced_at)
                ON CONFLICT(note_id) DO UPDATE SET
                    folder_name=excluded.folder_name,
                    title=excluded.title,
                    source_updated_at=excluded.source_updated_at,
                    content_hash=excluded.content_hash,
                    md_rel_path=excluded.md_rel_path,
                    is_deleted=excluded.is_deleted,
                    last_synced_at=excluded.last_synced_at
                """,
                asdict(state),
            )

    def upsert_asset_state(self, state: AssetState) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO assets_state(asset_id, note_id, source_asset_ref, asset_hash, asset_rel_path, last_synced_at)
                VALUES(:asset_id, :note_id, :source_asset_ref, :asset_hash, :asset_rel_path, :last_synced_at)
                ON CONFLICT(asset_id) DO UPDATE SET
                    note_id=excluded.note_id,
                    source_asset_ref=excluded.source_asset_ref,
                    asset_hash=excluded.asset_hash,
                    asset_rel_path=excluded.asset_rel_path,
                    last_synced_at=excluded.last_synced_at
                """,
                asdict(state),
            )

    def mark_missing_as_deleted(self, folder_name: str, source_ids: set[str]) -> int:
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT note_id, is_deleted FROM notes_state WHERE folder_name = ?", (folder_name,)
            ).fetchall()
            to_mark = [r["note_id"] for r in rows if r["note_id"] not in source_ids and int(r["is_deleted"]) == 0]
            for note_id in to_mark:
                conn.execute(
                    "UPDATE notes_state SET is_deleted = 1, last_synced_at = ? WHERE note_id = ?",
                    (_now_iso(), note_id),
                )
        return len(to_mark)
