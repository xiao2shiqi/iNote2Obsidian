from pathlib import Path

from inote2obsidian.config import (
    AppConfig,
    AppleNotesConfig,
    LoggingConfig,
    ObsidianConfig,
    StateConfig,
    SyncConfig,
)
from inote2obsidian.logging import configure_logging
from inote2obsidian.models import SourceNote
from inote2obsidian.sync_engine import run_sync


def _cfg(tmp_path: Path) -> AppConfig:
    return AppConfig(
        apple_notes=AppleNotesConfig(folder_name="Diary"),
        obsidian=ObsidianConfig(
            vault_path=str(tmp_path / "vault"),
            notes_subdir="AppleNotes",
            assets_subdir="AppleNotes/_assets",
        ),
        sync=SyncConfig(),
        state=StateConfig(db_path=str(tmp_path / "state.db")),
        logging=LoggingConfig(level="INFO", file_path=str(tmp_path / "sync.log")),
    )


def test_incremental_sync(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    logger = configure_logging(Path(cfg.logging.file_path), cfg.logging.level)

    notes = [
        SourceNote(
            note_id="n1",
            title="First",
            folder_name="Diary",
            updated_at="2026-03-03T00:00:00+00:00",
            body_plain="hello",
            body_html="",
            attachments=[],
        )
    ]

    status1, stats1 = run_sync(cfg, logger, source_fetcher=lambda _folder: notes)
    assert status1 == "success"
    assert stats1.added_count == 1

    status2, stats2 = run_sync(cfg, logger, source_fetcher=lambda _folder: notes)
    assert status2 == "success"
    assert stats2.skipped_count == 1


def test_tombstone_on_missing_note(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    logger = configure_logging(Path(cfg.logging.file_path), cfg.logging.level)

    notes = [
        SourceNote(
            note_id="n1",
            title="First",
            folder_name="Diary",
            updated_at="2026-03-03T00:00:00+00:00",
            body_plain="hello",
            body_html="",
            attachments=[],
        )
    ]

    run_sync(cfg, logger, source_fetcher=lambda _folder: notes)
    status, stats = run_sync(cfg, logger, source_fetcher=lambda _folder: [])
    assert status == "success"
    assert stats.deleted_count == 1
