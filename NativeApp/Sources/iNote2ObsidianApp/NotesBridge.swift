import Foundation

protocol NotesSnapshotProvider: Sendable {
    func fetchHeaders() throws -> [SourceNoteHeader]
    func fetchAllNotes() throws -> [SourceNote]
    func fetchSelectedNotes(noteIDs: Set<String>) throws -> [SourceNote]
    func streamAllNotes(onNote: @escaping @Sendable (SourceNote) -> Void) throws
    func streamNotes(noteIDs: Set<String>, onNote: @escaping @Sendable (SourceNote) -> Void) throws
}

final class AppleNotesBridge: NotesSnapshotProvider, @unchecked Sendable {
    func fetchHeaders() throws -> [SourceNoteHeader] {
        let (stdout, _) = try run(script: Self.headerScript, arguments: [])
        guard let data = stdout.data(using: .utf8) else {
            throw SyncError.bridgeFailed("Bridge output was not valid UTF-8.")
        }
        do {
            let rows = try JSONDecoder().decode([BridgeHeaderRow].self, from: data)
            return rows.map { row in
                SourceNoteHeader(
                    appleNoteID: row.noteID,
                    title: row.title,
                    folderPath: row.folderPath,
                    createdAt: Date(timeIntervalSince1970: row.createdAtMs / 1000),
                    updatedAt: Date(timeIntervalSince1970: row.updatedAtMs / 1000)
                )
            }
        } catch {
            throw SyncError.bridgeFailed("Failed to decode header output: \(error.localizedDescription)")
        }
    }

    func streamAllNotes(onNote: @escaping @Sendable (SourceNote) -> Void) throws {
        try streamNotesInternal(argument: "__ALL__", onNote: onNote)
    }

    func fetchAllNotes() throws -> [SourceNote] {
        try fetchSelectedNotes(noteIDs: [])
    }

    func fetchSelectedNotes(noteIDs: Set<String>) throws -> [SourceNote] {
        let argument = noteIDs.isEmpty ? "__ALL__" : try encodeNoteIDs(noteIDs)
        let (stdout, _) = try run(script: Self.noteFetchScript, arguments: [argument])
        guard let data = stdout.data(using: .utf8) else {
            throw SyncError.bridgeFailed("Bridge output was not valid UTF-8.")
        }
        do {
            let rows = try JSONDecoder().decode([BridgeNoteRow].self, from: data)
            return rows.map { row in
                SourceNote(
                    appleNoteID: row.noteID,
                    title: row.title,
                    folderPath: row.folderPath,
                    createdAt: Date(timeIntervalSince1970: row.createdAtMs / 1000),
                    updatedAt: Date(timeIntervalSince1970: row.updatedAtMs / 1000),
                    plainText: row.plainText ?? "",
                    htmlBody: row.htmlBody ?? ""
                )
            }
        } catch {
            throw SyncError.bridgeFailed("Failed to decode note output: \(error.localizedDescription)")
        }
    }

    func streamNotes(noteIDs: Set<String>, onNote: @escaping @Sendable (SourceNote) -> Void) throws {
        guard !noteIDs.isEmpty else { return }
        let noteIDsJSON = try encodeNoteIDs(noteIDs)
        try streamNotesInternal(argument: noteIDsJSON, onNote: onNote)
    }

    private func streamNotesInternal(argument: String, onNote: @escaping @Sendable (SourceNote) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.noteStreamScript, argument]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let pump = StreamPump(owner: self, onNote: onNote)
        let stdoutBox = DataBox()
        let group = DispatchGroup()

        do {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                while true {
                    let data = stderr.fileHandleForReading.availableData
                    if data.isEmpty {
                        break
                    }
                    pump.consume(data: data)
                }
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                stdoutBox.data = stdout.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            try process.run()
        } catch {
            throw SyncError.bridgeFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        group.wait()
        let stdoutText = String(data: stdoutBox.data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            if stdoutText.localizedCaseInsensitiveContains("not authorized") || stdoutText.localizedCaseInsensitiveContains("1743") {
                throw SyncError.permissionDenied
            }
            throw SyncError.bridgeFailed(stdoutText.isEmpty ? "osascript exited with code \(process.terminationStatus)" : stdoutText)
        }
        try pump.finish()
    }

    private struct BridgeHeaderRow: Decodable {
        var noteID: String
        var title: String
        var folderPath: String
        var createdAtMs: Double
        var updatedAtMs: Double

        private enum CodingKeys: String, CodingKey {
            case noteID = "note_id"
            case title
            case folderPath = "folder_path"
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
        }
    }

    private struct BridgeNoteRow: Decodable {
        var noteID: String
        var title: String
        var folderPath: String
        var createdAtMs: Double
        var updatedAtMs: Double
        var plainText: String?
        var htmlBody: String?

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

    fileprivate func decodeNoteRow(_ payload: String) throws -> SourceNote {
        guard let data = payload.data(using: .utf8) else {
            throw SyncError.bridgeFailed("Stream payload was not valid UTF-8.")
        }
        let row = try JSONDecoder().decode(BridgeNoteRow.self, from: data)
        return SourceNote(
            appleNoteID: row.noteID,
            title: row.title,
            folderPath: row.folderPath,
            createdAt: Date(timeIntervalSince1970: row.createdAtMs / 1000),
            updatedAt: Date(timeIntervalSince1970: row.updatedAtMs / 1000),
            plainText: row.plainText ?? "",
            htmlBody: row.htmlBody ?? ""
        )
    }

    private func encodeNoteIDs(_ noteIDs: Set<String>) throws -> String {
        let array = Array(noteIDs).sorted()
        let data = try JSONEncoder().encode(array)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SyncError.bridgeFailed("Failed to encode selected note IDs.")
        }
        return string
    }

    private func run(script: String, arguments: [String]) throws -> (String, String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-l", "JavaScript", "-e", script] + arguments

        let output = Pipe()
        let error = Pipe()
        task.standardOutput = output
        task.standardError = error
        let outputBox = DataBox()
        let errorBox = DataBox()
        let group = DispatchGroup()

        do {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                outputBox.data = output.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                errorBox.data = error.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            try task.run()
        } catch {
            throw SyncError.bridgeFailed(error.localizedDescription)
        }

        task.waitUntilExit()
        group.wait()
        let stdout = String(data: outputBox.data, encoding: .utf8) ?? ""
        let stderr = String(data: errorBox.data, encoding: .utf8) ?? ""
        if task.terminationStatus != 0 {
            if stderr.localizedCaseInsensitiveContains("not authorized") || stderr.localizedCaseInsensitiveContains("1743") {
                throw SyncError.permissionDenied
            }
            throw SyncError.bridgeFailed(stderr.isEmpty ? "osascript exited with code \(task.terminationStatus)" : stderr)
        }
        return (stdout, stderr)
    }

    private static let headerScript = #"""
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
        updated_at_ms: toEpochMs(note.modificationDate())
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

    private static let noteStreamScript = #"""
ObjC.import('Foundation');

function emit(tag, payload) {
  console.log(tag + "\t" + JSON.stringify(payload));
}

function toEpochMs(value) {
  try {
    return (new Date(value)).getTime();
  } catch (error) {
    return 0;
  }
}

function buildLookup(noteIDsJSON) {
  if (noteIDsJSON === '__ALL__') {
    return null;
  }
  var ids = JSON.parse(noteIDsJSON);
  var lookup = {};
  for (var i = 0; i < ids.length; i++) {
    lookup[String(ids[i])] = true;
  }
  return lookup;
}

function walkFolder(folder, parentPath, selected, remaining) {
  if (selected !== null && remaining.count <= 0) {
    return;
  }

  var folderName = String(folder.name() || '');
  if (!folderName || folderName === 'Recently Deleted') {
    return;
  }

  var currentPath = parentPath ? parentPath + '/' + folderName : folderName;
  var notes = [];
  try { notes = folder.notes(); } catch (error) { notes = []; }

  for (var i = 0; i < notes.length; i++) {
    if (selected !== null && remaining.count <= 0) {
      return;
    }

    var note = notes[i];
    var noteID = '';
    try {
      noteID = String(note.id());
    } catch (error) {
      continue;
    }

    if (selected !== null && !selected[noteID]) {
      continue;
    }

    try {
      emit('NOTE', {
        note_id: noteID,
        title: String(note.name() || ''),
        folder_path: currentPath,
        created_at_ms: toEpochMs(note.creationDate()),
        updated_at_ms: toEpochMs(note.modificationDate()),
        html_body: String(note.body() || '')
      });
      if (selected !== null) {
        delete selected[noteID];
        remaining.count -= 1;
      }
    } catch (error) {
    }
  }

  var children = [];
  try { children = folder.folders(); } catch (error) { children = []; }
  for (var j = 0; j < children.length; j++) {
    walkFolder(children[j], currentPath, selected, remaining);
  }
}

function run(argv) {
  var selected = buildLookup(argv[0]);
  var remaining = { count: selected === null ? -1 : Object.keys(selected).length };
  var app = Application('Notes');
  app.includeStandardAdditions = true;
  var accounts = app.accounts();

  for (var accountIndex = 0; accountIndex < accounts.length; accountIndex++) {
    var folders = [];
    try { folders = accounts[accountIndex].folders(); } catch (error) { folders = []; }
    for (var folderIndex = 0; folderIndex < folders.length; folderIndex++) {
      walkFolder(folders[folderIndex], '', selected, remaining);
      if (selected !== null && remaining.count <= 0) {
        return;
      }
    }
  }
} 
"""#

    private static let noteFetchScript = #"""
ObjC.import('Foundation');

function toEpochMs(value) {
  try {
    return (new Date(value)).getTime();
  } catch (error) {
    return 0;
  }
}

function buildLookup(noteIDsJSON) {
  if (noteIDsJSON === '__ALL__') {
    return null;
  }
  var ids = JSON.parse(noteIDsJSON);
  var lookup = {};
  for (var i = 0; i < ids.length; i++) {
    lookup[String(ids[i])] = true;
  }
  return lookup;
}

function walkFolder(folder, parentPath, selected, results) {
  var folderName = String(folder.name() || '');
  if (!folderName || folderName === 'Recently Deleted') {
    return;
  }

  var currentPath = parentPath ? parentPath + '/' + folderName : folderName;
  var notes = [];
  try { notes = folder.notes(); } catch (error) { notes = []; }

  for (var i = 0; i < notes.length; i++) {
    var note = notes[i];
    var noteID = '';
    try { noteID = String(note.id()); } catch (error) { continue; }
    if (selected !== null && !selected[noteID]) {
      continue;
    }

    try {
      results.push({
        note_id: noteID,
        title: String(note.name() || ''),
        folder_path: currentPath,
        created_at_ms: toEpochMs(note.creationDate()),
        updated_at_ms: toEpochMs(note.modificationDate()),
        html_body: String(note.body() || '')
      });
    } catch (error) {
    }
  }

  var children = [];
  try { children = folder.folders(); } catch (error) { children = []; }
  for (var j = 0; j < children.length; j++) {
    walkFolder(children[j], currentPath, selected, results);
  }
}

function run(argv) {
  var selected = buildLookup(argv[0]);
  var app = Application('Notes');
  app.includeStandardAdditions = true;
  var results = [];
  var accounts = app.accounts();

  for (var accountIndex = 0; accountIndex < accounts.length; accountIndex++) {
    var folders = [];
    try { folders = accounts[accountIndex].folders(); } catch (error) { folders = []; }
    for (var folderIndex = 0; folderIndex < folders.length; folderIndex++) {
      walkFolder(folders[folderIndex], '', selected, results);
    }
  }

  return JSON.stringify(results);
}
"""#
}

private final class StreamPump: @unchecked Sendable {
    private let owner: AppleNotesBridge
    private let onNote: @Sendable (SourceNote) -> Void
    private let lock = NSLock()
    private var buffer = ""

    init(owner: AppleNotesBridge, onNote: @escaping @Sendable (SourceNote) -> Void) {
        self.owner = owner
        self.onNote = onNote
    }

    func consume(data: Data) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
        let completeLines: [String]
        lock.lock()
        buffer.append(chunk)
        let lines = buffer.components(separatedBy: "\n")
        buffer = lines.last ?? ""
        completeLines = Array(lines.dropLast())
        lock.unlock()
        handle(lines: completeLines)
    }

    func finish() throws {
        lock.lock()
        let trailing = buffer
        buffer = ""
        lock.unlock()
        if !trailing.isEmpty {
            handle(lines: [trailing])
        }
    }

    private func handle(lines: [String]) {
        for line in lines where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, String(parts[0]) == "NOTE" else { continue }
            if let note = try? owner.decodeNoteRow(String(parts[1])) {
                onNote(note)
            }
        }
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
