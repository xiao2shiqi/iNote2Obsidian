from __future__ import annotations

import os
from pathlib import Path

from inote2obsidian.models import RenderedNote


def _atomic_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with tmp_path.open("wb") as fh:
        fh.write(content)
    os.replace(tmp_path, path)


def _extract_source_note_id(md_path: Path) -> str | None:
    if not md_path.exists():
        return None
    try:
        text = md_path.read_text(encoding="utf-8")
    except Exception:  # noqa: BLE001
        return None
    for line in text.splitlines():
        if line.startswith("source_note_id:"):
            value = line.split(":", 1)[1].strip().strip('"')
            return value or None
    return None


def _resolve_md_path(vault_path: Path, md_rel_path: str, source_note_id: str) -> Path:
    target = vault_path / md_rel_path
    if not target.exists():
        return target
    existing_note_id = _extract_source_note_id(target)
    if existing_note_id == source_note_id:
        return target
    stem, suffix = target.stem, target.suffix
    for idx in range(2, 1000):
        candidate = target.with_name(f"{stem}-{idx}{suffix}")
        if not candidate.exists():
            return candidate
        existing_note_id = _extract_source_note_id(candidate)
        if existing_note_id == source_note_id:
            return candidate
    raise RuntimeError(f"Unable to resolve unique markdown path for {md_rel_path}")


def write_rendered_note(vault_path: Path, rendered: RenderedNote, source_note_id: str) -> tuple[Path, list[Path]]:
    md_path = _resolve_md_path(vault_path, rendered.md_rel_path, source_note_id)
    _atomic_write(md_path, rendered.md_text.encode("utf-8"))

    written_assets: list[Path] = []
    for asset in rendered.assets_to_write:
        target = vault_path / asset.asset_rel_path
        binary = asset.attachment.binary_bytes
        if binary is None and asset.attachment.source_path:
            binary = Path(asset.attachment.source_path).read_bytes()
        if binary is None:
            continue
        _atomic_write(target, binary)
        written_assets.append(target)

    return md_path, written_assets
