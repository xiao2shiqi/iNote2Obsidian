from inote2obsidian.models import SourceNote
from inote2obsidian.parser import normalize_note


def test_normalize_extracts_inline_images_and_folder_path() -> None:
    html = '<div>Hello<br><img src="data:image/png;base64,iVBORw0KGgo=">World</div>'
    note = SourceNote(
        note_id='x-coredata://abc/ICNote/p1',
        title='T',
        folder_name='Work/子目录',
        updated_at='2026-03-04T00:00:00+00:00',
        body_plain='',
        body_html=html,
        attachments=[],
    )
    normalized = normalize_note(note)
    assert normalized.folder_name == 'Work/子目录'
    assert len(normalized.attachments) == 1
    assert normalized.attachments[0].filename.endswith('.png')
    assert 'Hello' in normalized.body_plain
    assert 'World' in normalized.body_plain
