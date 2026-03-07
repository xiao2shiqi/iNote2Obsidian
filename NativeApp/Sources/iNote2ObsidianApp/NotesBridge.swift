import Foundation

struct BridgeProgress {
    let scannedCount: Int
    let currentFolder: String?
    let heartbeatAt: Date
}

struct BridgeSummary {
    let totalNotes: Int
    let failedNotes: [BridgeFailedNote]
}

struct BridgeFailedNote {
    let noteID: String
    let title: String
    let folderPath: String
    let createdAt: Date
    let updatedAt: Date
    let errorDetail: String
}

final class NotesBridge {
    private static let noteStreamScript = #"""
ObjC.import('Foundation');

function emit(tag, payload) {
  try {
    console.log(tag + "\t" + JSON.stringify(payload));
  } catch (e) {
  }
}

function toEpochMs(d) {
  try {
    var time = (new Date(d)).getTime();
    if (isNaN(time)) { return null; }
    return time;
  } catch (e) { return null; }
}

function run(argv) {
  var excludeRecentlyDeleted = argv[0] === 'true';
  var app = Application('Notes');
  app.includeStandardAdditions = true;

  var scanned = 0;
  var lastHeartbeatAt = Date.now();

  function maybeHeartbeat(folderPath, force) {
    var now = Date.now();
    if (force || (scanned % 20) === 0 || (now - lastHeartbeatAt) >= 2000) {
      emit('HEARTBEAT', {
        scanned: scanned,
        current_folder: folderPath
      });
      lastHeartbeatAt = now;
    }
  }

    function walk(folder, parentPath) {
    var folderName = '';
    try { folderName = String(folder.name() || ''); } catch (e) { return; }
    if (!folderName) { return; }

    if (excludeRecentlyDeleted && folderName === 'Recently Deleted') {
      return;
    }

    var currentPath = parentPath ? (parentPath + '/' + folderName) : folderName;
    maybeHeartbeat(currentPath, true);

    var notes = [];
    try { notes = folder.notes(); } catch (e) { notes = []; }
    for (var i = 0; i < notes.length; i++) {
      var note = notes[i];
      var noteID = '';
      var noteTitle = '';
      var createdAtMs = null;
      var updatedAtMs = null;
      try {
        noteID = String(note.id());
        noteTitle = String(note.name() || '');
        createdAtMs = toEpochMs(note.creationDate());
        updatedAtMs = toEpochMs(note.modificationDate());
      } catch (e) {
        continue;
      }

      try {
        maybeHeartbeat(currentPath, true);
        var plain = '';
        try { plain = String(note.plaintext() || ''); } catch (e) { throw new Error('plaintext: ' + String(e)); }

        emit('NOTE', {
          note_id: noteID,
          title: noteTitle,
          folder_path: currentPath,
          created_at_ms: createdAtMs,
          updated_at_ms: updatedAtMs,
          body_plain: plain,
          body_html: ''
        });
      } catch (e) {
        emit('NOTE_ERROR', {
          note_id: noteID,
          title: noteTitle,
          folder_path: currentPath,
          created_at_ms: createdAtMs,
          updated_at_ms: updatedAtMs,
          error: String(e)
        });
      }

      scanned += 1;
      maybeHeartbeat(currentPath, false);
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

  emit('DONE', { total: scanned });
}
"""#

    private static let detailScript = #"""
ObjC.import('Foundation');

function toEpochMs(d) {
  try {
    var time = (new Date(d)).getTime();
    if (isNaN(time)) { return null; }
    return time;
  } catch (e) { return null; }
}

function walk(folder, parentPath, noteID) {
  var folderName = '';
  try { folderName = String(folder.name() || ''); } catch (e) { return null; }
  if (!folderName || folderName === 'Recently Deleted') { return null; }

  var currentPath = parentPath ? (parentPath + '/' + folderName) : folderName;

  var notes = [];
  try { notes = folder.notes(); } catch (e) { notes = []; }
  for (var i = 0; i < notes.length; i++) {
    try {
      var note = notes[i];
      if (String(note.id()) === noteID) {
        var plain = '';
        try { plain = String(note.plaintext() || ''); } catch (e) { plain = ''; }
        return {
          note_id: String(note.id()),
          title: String(note.name() || ''),
          folder_path: currentPath,
          created_at_ms: toEpochMs(note.creationDate()),
          updated_at_ms: toEpochMs(note.modificationDate()),
          body_plain: plain,
          body_html: ''
        };
      }
    } catch (e) {
    }
  }

  var children = [];
  try { children = folder.folders(); } catch (e) { children = []; }
  for (var j = 0; j < children.length; j++) {
    var found = walk(children[j], currentPath, noteID);
    if (found) { return found; }
  }
  return null;
}

function run(argv) {
  var noteID = argv[0];
  var app = Application('Notes');
  app.includeStandardAdditions = true;

  var accounts = app.accounts();
  for (var a = 0; a < accounts.length; a++) {
    var folders = [];
    try { folders = accounts[a].folders(); } catch (e) { folders = []; }
    for (var f = 0; f < folders.length; f++) {
      var found = walk(folders[f], '', noteID);
      if (found) {
        return JSON.stringify(found);
      }
    }
  }
  return '';
}
"""#

    private let decoder = JSONDecoder()

    func streamNotes(
        excludeRecentlyDeleted: Bool,
        cancellation: SyncCancellationController,
        onNote: @escaping (SourceNote) -> Void,
        onProgress: @escaping (BridgeProgress) -> Void
    ) throws -> BridgeSummary {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.noteStreamScript, excludeRecentlyDeleted ? "true" : "false"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let parser = NotesStreamParser(decoder: decoder, onNote: onNote, onProgress: onProgress)

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            parser.consumeStdoutData(data)
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            parser.consumeStderrData(data)
        }

        try process.run()
        let heartbeatTimeout: TimeInterval = 90

        while process.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
            if cancellation.isCancelled {
                process.terminate()
                throw SyncError.cancelled
            }
            if let parseErr = parser.parseError {
                process.terminate()
                throw SyncError.bridgeFailed("Bridge parse error: \(parseErr)")
            }
            if parser.isHeartbeatTimedOut(timeout: heartbeatTimeout) {
                process.terminate()
                throw SyncError.bridgeFailed("Bridge heartbeat timeout while reading Apple Notes")
            }
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

        let remainOut = stdout.fileHandleForReading.readDataToEndOfFile()
        if !remainOut.isEmpty {
            parser.consumeStdoutData(remainOut)
        }
        let remainErr = stderr.fileHandleForReading.readDataToEndOfFile()
        if !remainErr.isEmpty {
            parser.consumeStderrData(remainErr)
        }

        parser.flush()

        if cancellation.isCancelled {
            throw SyncError.cancelled
        }

        if let parseErr = parser.parseError {
            throw SyncError.bridgeFailed("Bridge parse error: \(parseErr)")
        }

        let stderrText = parser.stderrText
        if process.terminationStatus != 0 {
            if stderrText.localizedCaseInsensitiveContains("not authorized") || stderrText.localizedCaseInsensitiveContains("-1743") {
                throw SyncError.permissionDenied(stderrText)
            }
            throw SyncError.bridgeFailed(stderrText.isEmpty ? "Apple Notes bridge failed" : stderrText)
        }

        return BridgeSummary(
            totalNotes: parser.doneTotal ?? parser.scannedCount,
            failedNotes: parser.failedNotes
        )
    }

    func fetchNoteDetails(noteID: String, cancellation: SyncCancellationController) throws -> SourceNote? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.detailScript, noteID]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let timeout: TimeInterval = 20
        let start = Date()
        while process.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
            if cancellation.isCancelled {
                process.terminate()
                throw SyncError.cancelled
            }
            if Date().timeIntervalSince(start) > timeout {
                process.terminate()
                throw SyncError.bridgeFailed("Fallback note fetch timed out")
            }
        }

        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            if err.localizedCaseInsensitiveContains("not authorized") || err.localizedCaseInsensitiveContains("-1743") {
                throw SyncError.permissionDenied(err)
            }
            throw SyncError.bridgeFailed(err.isEmpty ? "Apple Notes fallback fetch failed" : err)
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }
        let raw = try decoder.decode(RawStreamNote.self, from: data)
        return raw.toSourceNote()
    }
}

private final class NotesStreamParser: @unchecked Sendable {
    private enum StreamSource {
        case stdout
        case stderr
    }

    private let decoder: JSONDecoder
    private let onNote: (SourceNote) -> Void
    private let onProgress: (BridgeProgress) -> Void
    private let queue = DispatchQueue(label: "inote.bridge.stream-parser")

    private var stdoutBuffer = Data()
    private var stderrEventBuffer = Data()
    private var stderrBuffer = ""
    private var _parseError: Error?
    private var _lastHeartbeatAt = Date()
    private var _scannedCount = 0
    private var _doneTotal: Int?
    private var _failedNotes: [BridgeFailedNote] = []

    init(decoder: JSONDecoder, onNote: @escaping (SourceNote) -> Void, onProgress: @escaping (BridgeProgress) -> Void) {
        self.decoder = decoder
        self.onNote = onNote
        self.onProgress = onProgress
    }

    func consumeStdoutData(_ data: Data) {
        consumeEventData(data, source: .stdout)
    }

    func consumeStderrData(_ data: Data) {
        consumeEventData(data, source: .stderr)
    }

    private func consumeEventData(_ data: Data, source: StreamSource) {
        queue.sync {
            switch source {
            case .stdout:
                stdoutBuffer.append(data)
            case .stderr:
                stderrEventBuffer.append(data)
            }

            var currentBuffer = source == .stdout ? stdoutBuffer : stderrEventBuffer
            while let newlineIndex = currentBuffer.firstIndex(of: 0x0A) {
                let lineData = currentBuffer.prefix(upTo: newlineIndex)
                currentBuffer.removeSubrange(...newlineIndex)
                processLineData(lineData, source: source)
            }
            if source == .stdout {
                stdoutBuffer = currentBuffer
            } else {
                stderrEventBuffer = currentBuffer
            }
        }
    }

    func flush() {
        queue.sync {
            if !stdoutBuffer.isEmpty {
                processLineData(stdoutBuffer, source: .stdout)
            }
            stdoutBuffer = Data()

            if !stderrEventBuffer.isEmpty {
                processLineData(stderrEventBuffer, source: .stderr)
            }
            stderrEventBuffer = Data()
        }
    }

    var parseError: Error? {
        queue.sync { _parseError }
    }

    var scannedCount: Int {
        queue.sync { _scannedCount }
    }

    var doneTotal: Int? {
        queue.sync { _doneTotal }
    }

    var stderrText: String {
        queue.sync { stderrBuffer }
    }

    var failedNotes: [BridgeFailedNote] {
        queue.sync { _failedNotes }
    }

    func isHeartbeatTimedOut(timeout: TimeInterval) -> Bool {
        queue.sync { Date().timeIntervalSince(_lastHeartbeatAt) > timeout }
    }

    private func processLine(_ line: String, source: StreamSource) {
        guard !line.isEmpty else { return }

        if line.hasPrefix("NOTE\t") {
            let raw = String(line.dropFirst(5))
            guard let data = raw.data(using: .utf8) else { return }
            do {
                let noteRaw = try decoder.decode(RawStreamNote.self, from: data)
                let note = noteRaw.toSourceNote()
                _scannedCount += 1
                _lastHeartbeatAt = Date()
                onNote(note)
                onProgress(BridgeProgress(scannedCount: _scannedCount, currentFolder: note.folderPath, heartbeatAt: _lastHeartbeatAt))
            } catch {
                _parseError = error
            }
            return
        }

        if line.hasPrefix("HEARTBEAT\t") {
            let raw = String(line.dropFirst(10))
            if let data = raw.data(using: .utf8), let payload = try? decoder.decode(HeartbeatPayload.self, from: data) {
                if let scanned = payload.scanned {
                    _scannedCount = max(_scannedCount, scanned)
                }
                _lastHeartbeatAt = Date()
                onProgress(BridgeProgress(scannedCount: _scannedCount, currentFolder: payload.currentFolder, heartbeatAt: _lastHeartbeatAt))
            }
            return
        }

        if line.hasPrefix("DONE\t") {
            let raw = String(line.dropFirst(5))
            if let data = raw.data(using: .utf8), let payload = try? decoder.decode(DonePayload.self, from: data) {
                _doneTotal = payload.total
                if let total = payload.total {
                    _scannedCount = max(_scannedCount, total)
                }
            }
            return
        }

        if line.hasPrefix("NOTE_ERROR\t") {
            let raw = String(line.dropFirst(11))
            guard let data = raw.data(using: .utf8) else { return }
            do {
                let failed = try decoder.decode(RawFailedNote.self, from: data).toBridgeFailedNote()
                _failedNotes.append(failed)
                _lastHeartbeatAt = Date()
            } catch {
                _parseError = error
            }
            return
        }

        if source == .stderr {
            stderrBuffer += line + "\n"
        }
    }

    private func processLineData(_ data: Data, source: StreamSource) {
        guard let line = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .newlines) else {
            if source == .stderr {
                stderrBuffer += "[non-utf8 line omitted]\n"
            }
            return
        }
        processLine(line, source: source)
    }
}

private struct HeartbeatPayload: Decodable {
    let scanned: Int?
    let currentFolder: String?

    enum CodingKeys: String, CodingKey {
        case scanned
        case currentFolder = "current_folder"
    }
}

private struct DonePayload: Decodable {
    let total: Int?
}

private struct RawFailedNote: Decodable {
    let noteID: String
    let title: String
    let folderPath: String
    let createdAtMs: Double?
    let updatedAtMs: Double?
    let error: String

    enum CodingKeys: String, CodingKey {
        case noteID = "note_id"
        case title
        case folderPath = "folder_path"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case error
    }

    func toBridgeFailedNote() -> BridgeFailedNote {
        let created = createdAtMs.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? Date(timeIntervalSince1970: 0)
        let updated = updatedAtMs.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? created
        return BridgeFailedNote(
            noteID: noteID,
            title: title.isEmpty ? "Untitled" : title,
            folderPath: folderPath,
            createdAt: created,
            updatedAt: updated,
            errorDetail: error
        )
    }
}

private struct RawStreamNote: Decodable {
    let noteID: String
    let title: String
    let folderPath: String
    let createdAtMs: Double?
    let updatedAtMs: Double?
    let bodyPlain: String
    let bodyHTML: String

    enum CodingKeys: String, CodingKey {
        case noteID = "note_id"
        case title
        case folderPath = "folder_path"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case bodyPlain = "body_plain"
        case bodyHTML = "body_html"
    }

    func toSourceNote() -> SourceNote {
        let created = createdAtMs.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? Date(timeIntervalSince1970: 0)
        let updated = updatedAtMs.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? created
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
