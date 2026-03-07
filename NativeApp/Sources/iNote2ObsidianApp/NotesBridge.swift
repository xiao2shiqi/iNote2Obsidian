import Foundation

protocol NotesSnapshotProvider: Sendable {
    func fetchSnapshot() throws -> [SourceNote]
}

final class AppleNotesBridge: NotesSnapshotProvider, @unchecked Sendable {
    func fetchSnapshot() throws -> [SourceNote] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-l", "JavaScript", "-e", Self.script]

        let output = Pipe()
        let error = Pipe()
        task.standardOutput = output
        task.standardError = error

        do {
            try task.run()
        } catch {
            throw SyncError.bridgeFailed(error.localizedDescription)
        }

        task.waitUntilExit()
        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if task.terminationStatus != 0 {
            if stderr.localizedCaseInsensitiveContains("not authorized") || stderr.localizedCaseInsensitiveContains("1743") {
                throw SyncError.permissionDenied
            }
            throw SyncError.bridgeFailed(stderr.isEmpty ? "osascript exited with code \(task.terminationStatus)" : stderr)
        }

        guard let data = stdout.data(using: .utf8) else {
            throw SyncError.bridgeFailed("Bridge output was not valid UTF-8.")
        }

        do {
            let rows = try JSONDecoder().decode([BridgeRow].self, from: data)
            return rows.map { row in
                SourceNote(
                    appleNoteID: row.noteID,
                    title: row.title,
                    folderPath: row.folderPath,
                    createdAt: Date(timeIntervalSince1970: row.createdAtMs / 1000),
                    updatedAt: Date(timeIntervalSince1970: row.updatedAtMs / 1000),
                    plainText: row.plainText,
                    htmlBody: row.htmlBody
                )
            }
        } catch {
            throw SyncError.bridgeFailed("Failed to decode bridge output: \(error.localizedDescription)")
        }
    }

    private struct BridgeRow: Decodable {
        var noteID: String
        var title: String
        var folderPath: String
        var createdAtMs: Double
        var updatedAtMs: Double
        var plainText: String
        var htmlBody: String

        private enum CodingKeys: String, CodingKey {
            case noteID = "note_id"
            case title
            case folderPath = "folder_path"
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
            case plainText = "plain_text"
            case htmlBody = "html_body"
        }
    }

    private static let script = #"""
ObjC.import('Foundation');

function toEpochMs(value) {
  try {
    return (new Date(value)).getTime();
  } catch (error) {
    return 0;
  }
}

function walkFolder(folder, parentPath, results) {
  var folderName = String(folder.name() || '');
  if (!folderName || folderName === 'Recently Deleted') {
    return;
  }

  var currentPath = parentPath ? parentPath + '/' + folderName : folderName;
  var notes = [];
  try { notes = folder.notes(); } catch (error) { notes = []; }

  for (var i = 0; i < notes.length; i++) {
    var note = notes[i];
    try {
      results.push({
        note_id: String(note.id()),
        title: String(note.name() || ''),
        folder_path: currentPath,
        created_at_ms: toEpochMs(note.creationDate()),
        updated_at_ms: toEpochMs(note.modificationDate()),
        plain_text: String(note.plaintext() || ''),
        html_body: String(note.body() || '')
      });
    } catch (error) {
    }
  }

  var children = [];
  try { children = folder.folders(); } catch (error) { children = []; }
  for (var j = 0; j < children.length; j++) {
    walkFolder(children[j], currentPath, results);
  }
}

function run() {
  var app = Application('Notes');
  app.includeStandardAdditions = true;
  var results = [];
  var accounts = app.accounts();

  for (var accountIndex = 0; accountIndex < accounts.length; accountIndex++) {
    var folders = [];
    try { folders = accounts[accountIndex].folders(); } catch (error) { folders = []; }
    for (var folderIndex = 0; folderIndex < folders.length; folderIndex++) {
      walkFolder(folders[folderIndex], '', results);
    }
  }

  return JSON.stringify(results);
}
"""#
}
