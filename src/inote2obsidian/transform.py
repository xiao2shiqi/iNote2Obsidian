from __future__ import annotations

import json
import hashlib
from datetime import datetime, timezone

from inote2obsidian.models import AssetToWrite, RenderedNote, SourceNote
from inote2obsidian.parser import (
    sanitize_note_id,
    sanitize_path_segment,
    slugify_title,
)


def build_md_filename(note_id: str, title: str) -> str:
    safe_id = sanitize_note_id(note_id)
    slug = slugify_title(title)
    return f"{safe_id}--{slug}.md"


def _frontmatter(note: SourceNote, now_iso: str, is_deleted: bool) -> str:
    deleted_value = "true" if is_deleted else "false"
    return (
        "---\n"
        "source: apple_notes\n"
        f'source_note_id: "{note.note_id}"\n'
        f'source_folder: "{note.folder_name}"\n'
        f'source_updated_at: "{note.updated_at}"\n'
        f'synced_at: "{now_iso}"\n'
        f"is_deleted_in_source: {deleted_value}\n"
        "---\n"
    )


def _join_rel(*parts: str) -> str:
    clean = [p.strip("/") for p in parts if p and p.strip("/")]
    return "/".join(clean)


def render_note(note: SourceNote, notes_subdir: str, assets_subdir: str, now_iso: str | None = None) -> RenderedNote:
    now_iso = now_iso or datetime.now(timezone.utc).isoformat()
    md_filename = build_md_filename(note.note_id, note.title)
    safe_id = sanitize_note_id(note.note_id)
    folder_rel = note.folder_name.strip("/") if note.folder_name else "Unknown"
    md_rel_path = _join_rel(notes_subdir, folder_rel, md_filename)

    lines: list[str] = [_frontmatter(note, now_iso, False), ""]
    body = note.body_plain.strip()
    if body:
        lines.append(body)

    assets_to_write: list[AssetToWrite] = []
    for idx, attachment in enumerate(note.attachments, start=1):
        filename = sanitize_path_segment(attachment.filename or f"asset-{idx}")
        asset_rel = _join_rel(notes_subdir, folder_rel, "_attachments", safe_id, filename)
        assets_to_write.append(AssetToWrite(attachment=attachment, asset_rel_path=asset_rel))
        lines.append("")
        lines.append(f"![{filename}](_attachments/{safe_id}/{filename})")

    md_text = "\n".join(lines).rstrip() + "\n"
    return RenderedNote(md_text=md_text, md_rel_path=md_rel_path, assets_to_write=assets_to_write)


def hash_text(payload: str, algo: str = "sha256") -> str:
    hasher = hashlib.new(algo)
    hasher.update(payload.encode("utf-8"))
    return hasher.hexdigest()


def hash_bytes(payload: bytes, algo: str = "sha256") -> str:
    hasher = hashlib.new(algo)
    hasher.update(payload)
    return hasher.hexdigest()


def note_fingerprint(note: SourceNote, algo: str = "sha256") -> str:
    payload = {
        "note_id": note.note_id,
        "title": note.title,
        "folder_name": note.folder_name,
        "updated_at": note.updated_at,
        "body_plain": note.body_plain,
        "attachments": [
            {
                "asset_id": a.asset_id,
                "filename": a.filename,
                "mime_type": a.mime_type,
                "source_asset_ref": a.source_asset_ref,
                "byte_size": len(a.binary_bytes) if a.binary_bytes is not None else None,
            }
            for a in note.attachments
        ],
    }
    serialized = json.dumps(payload, sort_keys=True, ensure_ascii=False)
    return hash_text(serialized, algo)
