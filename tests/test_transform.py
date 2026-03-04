from inote2obsidian.models import Attachment, SourceNote
from inote2obsidian.transform import build_md_filename, render_note


def test_slug_and_filename_stability() -> None:
    filename = build_md_filename("note-1", "My Diary: Day 1!", "2026-03-04T01:02:03+00:00")
    assert filename.startswith("2026-03-04 01:02:03--note-1-")
    assert filename.endswith("--my-diary-day-1.md")


def test_frontmatter_and_asset_reference() -> None:
    note = SourceNote(
        note_id="n1",
        title="Title",
        folder_name="Diary",
        updated_at="2026-03-03T00:00:00+00:00",
        body_plain="hello",
        body_html="",
        attachments=[
            Attachment(asset_id="a1", filename="img.png", mime_type="image/png", binary_bytes=b"png")
        ],
    )
    rendered = render_note(note, "AppleNotes", "AppleNotes/_assets", now_iso="2026-03-03T01:00:00+00:00")
    assert 'source_note_id: "n1"' in rendered.md_text
    assert "is_deleted_in_source: false" in rendered.md_text
    assert rendered.md_rel_path == "AppleNotes/Diary/2026-03-03 00:00:00--n1-40b3eab6--title.md"
    assert "![img.png](_attachments/n1-40b3eab6/img.png)" in rendered.md_text
    assert rendered.assets_to_write[0].asset_rel_path == "AppleNotes/Diary/_attachments/n1-40b3eab6/img.png"
