from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Attachment:
    asset_id: str
    filename: str
    mime_type: str
    binary_bytes: bytes | None = None
    source_asset_ref: str = ""
    source_path: str | None = None


@dataclass
class SourceNote:
    note_id: str
    title: str
    folder_name: str
    updated_at: str
    body_plain: str
    body_html: str
    created_at: str = ""
    attachments: list[Attachment] = field(default_factory=list)


@dataclass
class AssetToWrite:
    attachment: Attachment
    asset_rel_path: str


@dataclass
class RenderedNote:
    md_text: str
    md_rel_path: str
    assets_to_write: list[AssetToWrite] = field(default_factory=list)


@dataclass
class SyncStats:
    added_count: int = 0
    updated_count: int = 0
    deleted_count: int = 0
    skipped_count: int = 0
    error_count: int = 0


@dataclass
class RunContext:
    run_id: str
    started_at: str


@dataclass
class NoteState:
    note_id: str
    folder_name: str
    title: str
    source_updated_at: str
    content_hash: str
    md_rel_path: str
    is_deleted: int
    last_synced_at: str


@dataclass
class AssetState:
    asset_id: str
    note_id: str
    source_asset_ref: str
    asset_hash: str
    asset_rel_path: str
    last_synced_at: str


@dataclass
class RenderContext:
    notes_dir: Path
    assets_dir: Path
    now_iso: str
