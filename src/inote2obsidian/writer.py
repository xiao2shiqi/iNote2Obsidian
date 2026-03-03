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


def write_rendered_note(vault_path: Path, rendered: RenderedNote) -> tuple[Path, list[Path]]:
    md_path = vault_path / rendered.md_rel_path
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
