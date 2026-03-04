from __future__ import annotations

import base64
import hashlib
import html
import re
from datetime import datetime, timezone

from inote2obsidian.models import Attachment, SourceNote

_INVALID_FILENAME_CHARS = re.compile(r"[^a-z0-9-]+")
_INVALID_PATH_SEGMENT_CHARS = re.compile(r'[<>:"\\|?*\x00-\x1F]+')
_INLINE_IMAGE_RE = re.compile(
    r'<img[^>]+src=["\']data:(image/[a-zA-Z0-9.+-]+);base64,([^"\']+)["\'][^>]*>',
    re.IGNORECASE,
)
_MIME_EXT = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/gif": "gif",
    "image/webp": "webp",
    "image/heic": "heic",
    "image/heif": "heif",
}


def slugify_title(title: str) -> str:
    normalized = title.strip().lower()
    normalized = _INVALID_FILENAME_CHARS.sub("-", normalized)
    normalized = re.sub(r"-+", "-", normalized).strip("-")
    return normalized or "untitled"


def sanitize_note_id(note_id: str) -> str:
    raw = note_id.strip() or "note"
    tail = raw.split("/")[-1]
    tail = re.sub(r"[^a-zA-Z0-9_-]+", "-", tail).strip("-").lower() or "note"
    digest = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:8]
    return f"{tail}-{digest}"


def sanitize_path_segment(segment: str) -> str:
    clean = (segment or "").strip()
    clean = _INVALID_PATH_SEGMENT_CHARS.sub("-", clean)
    clean = clean.replace("/", "-")
    clean = re.sub(r"\s+", " ", clean).strip(" .")
    return clean or "Unknown"


def sanitize_folder_path(folder_path: str) -> str:
    parts = [p for p in (folder_path or "").split("/") if p.strip()]
    if not parts:
        return "Unknown"
    return "/".join(sanitize_path_segment(p) for p in parts)


def extract_inline_image_attachments(note_id: str, body_html: str) -> list[Attachment]:
    if not body_html:
        return []
    attachments: list[Attachment] = []
    for idx, match in enumerate(_INLINE_IMAGE_RE.finditer(body_html), start=1):
        mime_type = (match.group(1) or "image/jpeg").lower()
        b64_data = match.group(2) or ""
        try:
            binary = base64.b64decode(b64_data, validate=False)
        except Exception:  # noqa: BLE001
            continue
        if not binary:
            continue
        digest = hashlib.sha1(binary).hexdigest()[:12]
        ext = _MIME_EXT.get(mime_type, "bin")
        filename = f"inline-{idx}-{digest}.{ext}"
        attachments.append(
            Attachment(
                asset_id=f"{note_id}:inline:{idx}:{digest}",
                filename=filename,
                mime_type=mime_type,
                binary_bytes=binary,
                source_asset_ref=f"data:{mime_type}",
            )
        )
    return attachments


def html_to_text(body_html: str) -> str:
    if not body_html:
        return ""
    text = re.sub(r"(?i)<br\\s*/?>", "\n", body_html)
    text = re.sub(r"(?i)</div>", "\n", text)
    text = re.sub(r"(?i)</p>", "\n", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


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
    attachments = list(note.attachments)
    if note.body_html:
        inline = extract_inline_image_attachments(note.note_id.strip(), note.body_html)
        if inline:
            attachments.extend(inline)
    body_plain = (note.body_plain or "").strip()
    if not body_plain and note.body_html:
        body_plain = html_to_text(note.body_html)

    return SourceNote(
        note_id=note.note_id.strip(),
        title=title,
        folder_name=sanitize_folder_path(folder_name),
        updated_at=normalize_iso8601(note.updated_at),
        created_at=normalize_iso8601(note.created_at or note.updated_at),
        body_plain=body_plain,
        body_html=note.body_html or "",
        attachments=attachments,
    )
