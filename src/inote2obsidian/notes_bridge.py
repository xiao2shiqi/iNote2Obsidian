from __future__ import annotations

import json
import subprocess

from inote2obsidian.models import Attachment, SourceNote

JXA_SCRIPT = r'''
ObjC.import('Foundation');

function run(argv) {
  var folderName = argv[0];
  var includeAll = folderName === "*" || folderName === "__ALL__";
  var app = Application('Notes');
  app.includeStandardAdditions = true;

  var out = [];
  var accounts = app.accounts();
  for (var i = 0; i < accounts.length; i++) {
    var folders = accounts[i].folders();
    for (var j = 0; j < folders.length; j++) {
      var folder = folders[j];
      if (!includeAll && folder.name() !== folderName) {
        continue;
      }
      var notes = folder.notes();
      for (var k = 0; k < notes.length; k++) {
        var note = notes[k];
        var item = {
          note_id: String(note.id()),
          title: String(note.name() || ''),
          folder_name: String(folder.name() || ''),
          updated_at: String(note.modificationDate()),
          body_plain: String(note.plaintext() || ''),
          body_html: String(note.body() || ''),
          attachments: []
        };
        out.push(item);
      }
    }
  }

  return JSON.stringify(out);
}
'''


def fetch_notes_from_apple_notes(folder_name: str) -> list[SourceNote]:
    cmd = ["osascript", "-l", "JavaScript", "-e", JXA_SCRIPT, folder_name]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        stderr = proc.stderr.strip()
        raise RuntimeError(f"osascript failed: {stderr}")

    payload = json.loads(proc.stdout or "[]")
    notes: list[SourceNote] = []
    for raw in payload:
        attachments = [
            Attachment(
                asset_id=a.get("asset_id", ""),
                filename=a.get("filename", ""),
                mime_type=a.get("mime_type", "application/octet-stream"),
                binary_bytes=None,
                source_asset_ref=a.get("source_asset_ref", ""),
                source_path=a.get("source_path"),
            )
            for a in raw.get("attachments", [])
            if isinstance(a, dict)
        ]
        notes.append(
            SourceNote(
                note_id=str(raw.get("note_id", "")),
                title=str(raw.get("title", "")),
                folder_name=str(raw.get("folder_name", folder_name)),
                updated_at=str(raw.get("updated_at", "")),
                body_plain=str(raw.get("body_plain", "")),
                body_html=str(raw.get("body_html", "")),
                attachments=attachments,
            )
        )
    return notes
