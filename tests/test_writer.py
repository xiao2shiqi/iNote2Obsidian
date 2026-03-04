from pathlib import Path

from inote2obsidian.models import Attachment, AssetToWrite, RenderedNote
from inote2obsidian.writer import write_rendered_note


def test_write_note_and_assets(tmp_path: Path) -> None:
    rendered = RenderedNote(
        md_text="# Hello\n",
        md_rel_path="AppleNotes/n1--hello.md",
        assets_to_write=[
            AssetToWrite(
                attachment=Attachment(
                    asset_id="a1",
                    filename="img.png",
                    mime_type="image/png",
                    binary_bytes=b"123",
                ),
                asset_rel_path="AppleNotes/_assets/n1/img.png",
            )
        ],
    )

    md_path, assets = write_rendered_note(tmp_path, rendered, "n1")
    assert md_path.exists()
    assert md_path.read_text(encoding="utf-8") == "# Hello\n"
    assert len(assets) == 1
    assert assets[0].read_bytes() == b"123"
