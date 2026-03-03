from pathlib import Path

from inote2obsidian.models import NoteState
from inote2obsidian.state_db import StateDB


def test_note_upsert_and_mark_deleted(tmp_path: Path) -> None:
    db = StateDB(tmp_path / "state.db")
    db.init_schema()
    db.upsert_note_state(
        NoteState(
            note_id="n1",
            folder_name="Diary",
            title="T",
            source_updated_at="2026-03-03T00:00:00+00:00",
            content_hash="h1",
            md_rel_path="AppleNotes/n1--t.md",
            is_deleted=0,
            last_synced_at="2026-03-03T00:00:00+00:00",
        )
    )

    state = db.get_note_state("n1")
    assert state is not None
    assert state.content_hash == "h1"

    deleted = db.mark_missing_as_deleted("Diary", source_ids=set())
    assert deleted == 1
    state2 = db.get_note_state("n1")
    assert state2 is not None
    assert state2.is_deleted == 1
