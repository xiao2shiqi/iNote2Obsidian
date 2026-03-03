from __future__ import annotations

import re
from datetime import datetime, timezone

from inote2obsidian.models import SourceNote

_INVALID_FILENAME_CHARS = re.compile(r"[^a-z0-9-]+")


def slugify_title(title: str) -> str:
    normalized = title.strip().lower()
    normalized = _INVALID_FILENAME_CHARS.sub("-", normalized)
    normalized = re.sub(r"-+", "-", normalized).strip("-")
    return normalized or "untitled"


def normalize_iso8601(value: str) -> str:
    if not value:
        return datetime.now(timezone.utc).isoformat()
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return datetime.now(timezone.utc).isoformat()
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat()


def normalize_note(note: SourceNote) -> SourceNote:
    title = (note.title or "").strip() or "Untitled"
    folder_name = (note.folder_name or "").strip() or "Unknown"
    return SourceNote(
        note_id=note.note_id.strip(),
        title=title,
        folder_name=folder_name,
        updated_at=normalize_iso8601(note.updated_at),
        body_plain=note.body_plain or "",
        body_html=note.body_html or "",
        attachments=note.attachments,
    )
