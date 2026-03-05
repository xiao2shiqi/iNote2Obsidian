import Foundation

final class NotesBridge {
    private static let script = #"""
ObjC.import('Foundation');

function run(argv) {
  var excludeRecentlyDeleted = argv[0] === 'true';
  var app = Application('Notes');
  app.includeStandardAdditions = true;

  var out = [];

  function toISO(d) {
    try { return (new Date(d)).toISOString(); } catch (e) { return ''; }
  }

  function walk(folder, parentPath) {
    var folderName = '';
    try { folderName = String(folder.name() || ''); } catch (e) { return; }
    if (!folderName) { return; }

    if (excludeRecentlyDeleted && folderName === 'Recently Deleted') {
      return;
    }

    var currentPath = parentPath ? (parentPath + '/' + folderName) : folderName;

    var notes = [];
    try { notes = folder.notes(); } catch (e) { notes = []; }
    for (var i = 0; i < notes.length; i++) {
      try {
        var note = notes[i];
        out.push({
          note_id: String(note.id()),
          title: String(note.name() || ''),
          folder_path: currentPath,
          created_at: toISO(note.creationDate()),
          updated_at: toISO(note.modificationDate()),
          body_plain: String(note.plaintext() || ''),
          body_html: String(note.body() || '')
        });
      } catch (e) {
      }
    }

    var children = [];
    try { children = folder.folders(); } catch (e) { children = []; }
    for (var j = 0; j < children.length; j++) {
      walk(children[j], currentPath);
    }
  }

  var accounts = app.accounts();
  for (var a = 0; a < accounts.length; a++) {
    var folders = [];
    try { folders = accounts[a].folders(); } catch (e) { folders = []; }
    for (var f = 0; f < folders.length; f++) {
      walk(folders[f], '');
    }
  }

  return JSON.stringify(out);
}
"""#

    private let decoder = JSONDecoder()

    func fetchNotes(excludeRecentlyDeleted: Bool) throws -> [SourceNote] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.script, excludeRecentlyDeleted ? "true" : "false"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let timeout: TimeInterval = 120
        let start = Date()
        while process.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
            if Date().timeIntervalSince(start) > timeout {
                process.terminate()
                throw SyncError.bridgeFailed("Timed out while reading Apple Notes")
            }
        }

        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            if err.localizedCaseInsensitiveContains("not authorized") || err.localizedCaseInsensitiveContains("-1743") {
                throw SyncError.permissionDenied(err)
            }
            throw SyncError.bridgeFailed(err)
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return [] }
        let raws = try decoder.decode([RawNote].self, from: data)
        return raws.compactMap { $0.toSourceNote() }
    }
}

private struct RawNote: Decodable {
    let noteID: String
    let title: String
    let folderPath: String
    let createdAt: String
    let updatedAt: String
    let bodyPlain: String
    let bodyHTML: String

    enum CodingKeys: String, CodingKey {
        case noteID = "note_id"
        case title
        case folderPath = "folder_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case bodyPlain = "body_plain"
        case bodyHTML = "body_html"
    }

    func toSourceNote() -> SourceNote? {
        let iso = ISO8601DateFormatter()
        guard let created = iso.date(from: createdAt), let updated = iso.date(from: updatedAt) else {
            return nil
        }
        return SourceNote(
            noteID: noteID,
            title: title.isEmpty ? "Untitled" : title,
            folderPath: folderPath,
            createdAt: created,
            updatedAt: updated,
            bodyPlain: bodyPlain,
            bodyHTML: bodyHTML,
            inlineAttachments: InlineAttachmentExtractor.extract(from: bodyHTML)
        )
    }
}

private enum InlineAttachmentExtractor {
    static func extract(from html: String) -> [SourceAttachment] {
        guard !html.isEmpty else { return [] }
        let pattern = #"<img[^>]+src=["']data:(image/[a-zA-Z0-9.+-]+);base64,([^"']+)["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            let mime = ns.substring(with: match.range(at: 1)).lowercased()
            let b64 = ns.substring(with: match.range(at: 2))
            guard let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]) else {
                return nil
            }
            return SourceAttachment(mimeType: mime, data: data)
        }
    }
}
