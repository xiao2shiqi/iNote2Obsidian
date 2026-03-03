from __future__ import annotations

import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from inote2obsidian.config import AppConfig
from inote2obsidian.models import AssetState, NoteState, SourceNote, SyncStats
from inote2obsidian.notes_bridge import fetch_notes_from_apple_notes
from inote2obsidian.parser import normalize_note
from inote2obsidian.state_db import StateDB
from inote2obsidian.transform import hash_bytes, note_fingerprint, render_note
from inote2obsidian.writer import write_rendered_note


def run_sync(
    config: AppConfig,
    logger: logging.Logger,
    source_fetcher: Callable[[str], list[SourceNote]] | None = None,
) -> tuple[str, SyncStats]:
    source_fetcher = source_fetcher or fetch_notes_from_apple_notes
    db = StateDB(Path(config.state.db_path))
    db.init_schema()

    run = db.start_run()
    stats = SyncStats()
    status = "success"

    logger.info("sync started", extra={"run_id": run.run_id, "stage": "sync"})

    try:
        notes = [normalize_note(n) for n in source_fetcher(config.apple_notes.folder_name)]
        source_ids = {n.note_id for n in notes}

        for note in notes:
            try:
                rendered = render_note(
                    note=note,
                    notes_subdir=config.obsidian.notes_subdir,
                    assets_subdir=config.obsidian.assets_subdir,
                    now_iso=datetime.now(timezone.utc).isoformat(),
                )

                content_hash = note_fingerprint(note, config.sync.hash_algo)
                prev = db.get_note_state(note.note_id)
                if prev and prev.content_hash == content_hash and prev.is_deleted == 0:
                    stats.skipped_count += 1
                    continue

                _, written_assets = write_rendered_note(Path(config.obsidian.vault_path), rendered)
                now_iso = datetime.now(timezone.utc).isoformat()
                db.upsert_note_state(
                    NoteState(
                        note_id=note.note_id,
                        folder_name=note.folder_name,
                        title=note.title,
                        source_updated_at=note.updated_at,
                        content_hash=content_hash,
                        md_rel_path=rendered.md_rel_path,
                        is_deleted=0,
                        last_synced_at=now_iso,
                    )
                )

                for idx, written in enumerate(written_assets, start=1):
                    binary = written.read_bytes()
                    db.upsert_asset_state(
                        AssetState(
                            asset_id=f"{note.note_id}:{idx}:{written.name}",
                            note_id=note.note_id,
                            source_asset_ref=str(written),
                            asset_hash=hash_bytes(binary, config.sync.hash_algo),
                            asset_rel_path=str(written.relative_to(Path(config.obsidian.vault_path))),
                            last_synced_at=now_iso,
                        )
                    )

                if prev is None:
                    stats.added_count += 1
                else:
                    stats.updated_count += 1
            except Exception as exc:  # noqa: BLE001
                stats.error_count += 1
                status = "partial"
                logger.error(
                    f"note sync failed: {exc}",
                    extra={"run_id": run.run_id, "note_id": note.note_id, "stage": "note"},
                )

        deleted_count = db.mark_missing_as_deleted(config.apple_notes.folder_name, source_ids)
        stats.deleted_count += deleted_count
        if stats.error_count > 0 and status == "success":
            status = "partial"

    except Exception as exc:  # noqa: BLE001
        status = "failed"
        stats.error_count += 1
        logger.critical(
            f"sync failed: {exc}", extra={"run_id": run.run_id, "stage": "sync"}
        )

    db.finish_run(run.run_id, status, stats)
    logger.info(
        "sync finished",
        extra={
            "run_id": run.run_id,
            "stage": "sync",
            "added": stats.added_count,
            "updated": stats.updated_count,
            "deleted": stats.deleted_count,
            "errors": stats.error_count,
            "skipped": stats.skipped_count,
        },
    )
    return status, stats
