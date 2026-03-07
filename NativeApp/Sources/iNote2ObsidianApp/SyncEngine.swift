import Foundation

private enum PendingSyncKind {
    case create
    case update
    case move
}

private struct PendingSync {
    var kind: PendingSyncKind
    var header: SourceNoteHeader
    var previous: ManagedNoteState?
    var stableBaseName: String
    var noteRelativePath: String
    var assetRelativeDir: String
}

private final class DetailProcessingState: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var pendingByID: [String: PendingSync]
    private(set) var summary: SyncRunSummary

    init(pendingByID: [String: PendingSync], summary: SyncRunSummary) {
        self.pendingByID = pendingByID
        self.summary = summary
    }

    func withMutation<T>(_ body: (inout [String: PendingSync], inout SyncRunSummary) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&pendingByID, &summary)
    }
}

private final class InitialSyncState: @unchecked Sendable {
    private let lock = NSLock()
    private var usedBaseNames = Set<String>()
    private var seenNoteIDs = Set<String>()
    private(set) var summary: SyncRunSummary

    init(summary: SyncRunSummary) {
        self.summary = summary
    }

    func allocateBaseName(for createdAt: Date, planner: SyncPlanner) -> String {
        lock.lock()
        defer { lock.unlock() }
        return planner.allocateBaseName(for: createdAt, used: &usedBaseNames)
    }

    func recordCreate(noteID: String, warnings: Int) {
        lock.lock()
        seenNoteIDs.insert(noteID)
        summary.scannedCount += 1
        summary.createdCount += 1
        summary.warningCount += warnings
        lock.unlock()
    }

    func recordError() {
        lock.lock()
        summary.errorCount += 1
        lock.unlock()
    }

    func missingNoteIDs(from headers: [SourceNoteHeader]) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        let headerIDs = Set(headers.map(\.appleNoteID))
        return headerIDs.subtracting(seenNoteIDs)
    }
}

struct SyncPlanner {
    fileprivate func pendingSync(
        for header: SourceNoteHeader,
        existing state: ManagedNoteState?,
        settings: AppSettings,
        usedBaseNames: inout Set<String>
    ) -> PendingSync? {
        let baseName = state.map { Self.baseName(from: $0.noteRelativePath) }.flatMap { $0.isEmpty ? nil : $0 }
            ?? allocateBaseName(for: header.createdAt, used: &usedBaseNames)
        usedBaseNames.insert(baseName)

        let folder = sanitizeFolderPath(header.folderPath)
        let noteRelativePath = folder.isEmpty ? "\(baseName).md" : "\(folder)/\(baseName).md"
        let assetRelativeDir = "\(settings.attachmentsFolderName)/\(baseName)"

        guard let state else {
            return PendingSync(
                kind: .create,
                header: header,
                previous: nil,
                stableBaseName: baseName,
                noteRelativePath: noteRelativePath,
                assetRelativeDir: assetRelativeDir
            )
        }

        if state.noteRelativePath != noteRelativePath || state.assetRelativeDir != assetRelativeDir || state.sourceFolderPath != header.folderPath {
            return PendingSync(
                kind: .move,
                header: header,
                previous: state,
                stableBaseName: baseName,
                noteRelativePath: noteRelativePath,
                assetRelativeDir: assetRelativeDir
            )
        }

        if state.updatedAt != Self.isoString(header.updatedAt) || state.isDeleted {
            return PendingSync(
                kind: .update,
                header: header,
                previous: state,
                stableBaseName: baseName,
                noteRelativePath: noteRelativePath,
                assetRelativeDir: assetRelativeDir
            )
        }

        return nil
    }

    func plan(
        notes: [SourceNote],
        existingStates: [ManagedNoteState],
        settings: AppSettings
    ) -> [SyncAction] {
        let statesByID = Dictionary(uniqueKeysWithValues: existingStates.map { ($0.appleNoteID, $0) })
        var actions: [SyncAction] = []
        var usedBaseNames = Set(existingStates.map { Self.baseName(from: $0.noteRelativePath) }.filter { !$0.isEmpty })

        for note in notes.sorted(by: { $0.createdAt < $1.createdAt }) {
            let state = statesByID[note.appleNoteID]
            let baseName = state.map { Self.baseName(from: $0.noteRelativePath) }.flatMap { $0.isEmpty ? nil : $0 }
                ?? allocateBaseName(for: note.createdAt, used: &usedBaseNames)
            usedBaseNames.insert(baseName)

            let folder = sanitizeFolderPath(note.folderPath)
            let noteRelativePath = folder.isEmpty ? "\(baseName).md" : "\(folder)/\(baseName).md"
            let assetRelativeDir = "\(settings.attachmentsFolderName)/\(baseName)"
            let planned = PlannedNote(
                note: note,
                stableBaseName: baseName,
                noteRelativePath: noteRelativePath,
                assetRelativeDir: assetRelativeDir
            )

            guard let state else {
                actions.append(.create(planned))
                continue
            }

            let probe = MarkdownRenderer().render(
                note: note,
                stableBaseName: baseName,
                noteRelativePath: noteRelativePath,
                assetRelativeDir: assetRelativeDir
            )

            if state.noteRelativePath != noteRelativePath || state.assetRelativeDir != assetRelativeDir {
                actions.append(.move(planned, previous: state))
            } else if state.updatedAt != Self.isoString(note.updatedAt)
                || state.contentHash != probe.contentHash
                || state.assetManifestHash != probe.assetManifestHash
                || state.isDeleted
            {
                actions.append(.update(planned, previous: state))
            } else {
                actions.append(.noop(planned, previous: state))
            }
        }

        let seenIDs = Set(notes.map(\.appleNoteID))
        for state in existingStates where !seenIDs.contains(state.appleNoteID) && !state.isDeleted {
            let nextMissingCount = state.missingScanCount + 1
            if nextMissingCount >= 2 {
                actions.append(.delete(state))
            } else {
                actions.append(.markMissing(state, nextMissingCount: nextMissingCount))
            }
        }

        return actions
    }

    func allocateBaseName(for createdAt: Date, used: inout Set<String>) -> String {
        let root = Self.fileNameFormatter.string(from: createdAt)
        if !used.contains(root) {
            used.insert(root)
            return root
        }
        for suffix in 1...9_999 {
            let candidate = "\(root)-\(suffix)"
            if !used.contains(candidate) {
                used.insert(candidate)
                return candidate
            }
        }
        return "\(root)-overflow"
    }

    func sanitizeFolderPath(_ path: String) -> String {
        path
            .split(separator: "/")
            .map { component in
                let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = trimmed.components(separatedBy: CharacterSet(charactersIn: "<>:\"\\|?*\0")).joined(separator: "-")
                return cleaned.isEmpty ? "Untitled" : cleaned
            }
            .joined(separator: "/")
    }

    private static func baseName(from relativePath: String) -> String {
        ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

}

final class SyncEngine: @unchecked Sendable {
    private let planner = SyncPlanner()
    private let renderer = MarkdownRenderer()
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func run(
        settings: AppSettings,
        snapshotProvider: NotesSnapshotProvider,
        stateStore: StateStore,
        logger: AppLogger
    ) throws -> SyncRunSummary {
        let vaultURL = URL(fileURLWithPath: settings.vaultPath, isDirectory: true)
        guard fileManager.fileExists(atPath: vaultURL.path) else {
            throw SyncError.invalidVaultPath
        }

        let startedAt = Date()
        let existingStates = try stateStore.fetchStates()
        let now = SyncPlanner.isoString(Date())

        if existingStates.isEmpty {
            logger.info("initial sync started")
            let initialState = InitialSyncState(
                summary: SyncRunSummary(
                    scannedCount: 0,
                    createdCount: 0,
                    updatedCount: 0,
                    movedCount: 0,
                    deletedCount: 0,
                    warningCount: 0,
                    errorCount: 0,
                    duration: 0
                )
            )
            try snapshotProvider.streamAllNotes { note in
                do {
                    let baseName = initialState.allocateBaseName(for: note.createdAt, planner: self.planner)
                    let folder = self.planner.sanitizeFolderPath(note.folderPath)
                    let noteRelativePath = folder.isEmpty ? "\(baseName).md" : "\(folder)/\(baseName).md"
                    let assetRelativeDir = "\(settings.attachmentsFolderName)/\(baseName)"
                    let planned = PlannedNote(
                        note: note,
                        stableBaseName: baseName,
                        noteRelativePath: noteRelativePath,
                        assetRelativeDir: assetRelativeDir
                    )
                    let rendered = self.renderer.render(
                        note: note,
                        stableBaseName: baseName,
                        noteRelativePath: noteRelativePath,
                        assetRelativeDir: assetRelativeDir
                    )
                    try self.write(planned: planned, rendered: rendered, vaultURL: vaultURL)
                    try stateStore.upsert(self.makeState(from: planned, rendered: rendered, seenAt: now))
                    initialState.recordCreate(noteID: note.appleNoteID, warnings: rendered.warnings.count)
                    logger.info("created \(planned.noteRelativePath)")
                } catch {
                    initialState.recordError()
                    logger.error(error.localizedDescription)
                }
            }

            let postHeaders = try snapshotProvider.fetchHeaders()
            let missingNoteIDs = initialState.missingNoteIDs(from: postHeaders)
            if !missingNoteIDs.isEmpty {
                logger.info("initial sync reconcile: \(missingNoteIDs.count) notes")
                let missingNotes = try snapshotProvider.fetchSelectedNotes(noteIDs: missingNoteIDs)
                for note in missingNotes.sorted(by: { $0.createdAt < $1.createdAt }) {
                    do {
                        let baseName = initialState.allocateBaseName(for: note.createdAt, planner: self.planner)
                        let folder = self.planner.sanitizeFolderPath(note.folderPath)
                        let noteRelativePath = folder.isEmpty ? "\(baseName).md" : "\(folder)/\(baseName).md"
                        let assetRelativeDir = "\(settings.attachmentsFolderName)/\(baseName)"
                        let planned = PlannedNote(
                            note: note,
                            stableBaseName: baseName,
                            noteRelativePath: noteRelativePath,
                            assetRelativeDir: assetRelativeDir
                        )
                        let rendered = self.renderer.render(
                            note: note,
                            stableBaseName: baseName,
                            noteRelativePath: noteRelativePath,
                            assetRelativeDir: assetRelativeDir
                        )
                        try self.write(planned: planned, rendered: rendered, vaultURL: vaultURL)
                        try stateStore.upsert(self.makeState(from: planned, rendered: rendered, seenAt: now))
                        initialState.recordCreate(noteID: note.appleNoteID, warnings: rendered.warnings.count)
                        logger.info("created \(planned.noteRelativePath)")
                    } catch {
                        initialState.recordError()
                        logger.error(error.localizedDescription)
                    }
                }
            }

            var initialSummary = initialState.summary
            initialSummary.duration = Date().timeIntervalSince(startedAt)
            logger.info(
                "run finished: created=\(initialSummary.createdCount) updated=\(initialSummary.updatedCount) moved=\(initialSummary.movedCount) deleted=\(initialSummary.deletedCount) warnings=\(initialSummary.warningCount) errors=\(initialSummary.errorCount)"
            )
            return initialSummary
        }

        let headers = try snapshotProvider.fetchHeaders().sorted(by: { $0.createdAt < $1.createdAt })
        let statesByID = Dictionary(uniqueKeysWithValues: existingStates.map { ($0.appleNoteID, $0) })
        var usedBaseNames = Set(existingStates.map { Self.baseName(from: $0.noteRelativePath) }.filter { !$0.isEmpty })
        var seenIDs = Set<String>()
        var pendingByID: [String: PendingSync] = [:]

        var summary = SyncRunSummary(
            scannedCount: headers.count,
            createdCount: 0,
            updatedCount: 0,
            movedCount: 0,
            deletedCount: 0,
            warningCount: 0,
            errorCount: 0,
            duration: 0
        )

        logger.info("header scan complete: \(headers.count) notes")

        for header in headers {
            seenIDs.insert(header.appleNoteID)
            if let pending = planner.pendingSync(
                for: header,
                existing: statesByID[header.appleNoteID],
                settings: settings,
                usedBaseNames: &usedBaseNames
            ) {
                pendingByID[header.appleNoteID] = pending
                logger.info("queued \(pending.kind.logLabel) \(pending.noteRelativePath)")
            } else if var state = statesByID[header.appleNoteID] {
                state.updatedAt = SyncPlanner.isoString(header.updatedAt)
                state.sourceFolderPath = header.folderPath
                state.lastSeenAt = now
                state.missingScanCount = 0
                state.isDeleted = false
                try stateStore.upsert(state)
            }
        }

        for state in existingStates where !seenIDs.contains(state.appleNoteID) && !state.isDeleted {
            do {
                if state.missingScanCount + 1 >= 2 {
                    try removeRenderedFiles(for: state, vaultURL: vaultURL)
                    var deletedState = state
                    deletedState.isDeleted = true
                    deletedState.missingScanCount = 2
                    deletedState.lastSeenAt = now
                    try stateStore.upsert(deletedState)
                    logger.info("deleted \(state.noteRelativePath)")
                    summary.deletedCount += 1
                } else {
                    var missingState = state
                    missingState.missingScanCount += 1
                    missingState.lastSeenAt = now
                    try stateStore.upsert(missingState)
                    logger.info("missing once \(state.noteRelativePath)")
                }
            } catch {
                summary.errorCount += 1
                logger.error(error.localizedDescription)
            }
        }

        logger.info("detail fetch queue: \(pendingByID.count) notes")
        let fetchedNotes = try snapshotProvider.fetchSelectedNotes(noteIDs: Set(pendingByID.keys))

        for note in fetchedNotes {
            guard let pending = pendingByID[note.appleNoteID] else { continue }
            do {
                let planned = PlannedNote(
                    note: note,
                    stableBaseName: pending.stableBaseName,
                    noteRelativePath: pending.noteRelativePath,
                    assetRelativeDir: pending.assetRelativeDir
                )
                let rendered = self.renderer.render(
                    note: note,
                    stableBaseName: planned.stableBaseName,
                    noteRelativePath: planned.noteRelativePath,
                    assetRelativeDir: planned.assetRelativeDir
                )
                if let previous = pending.previous, pending.kind == .move {
                    try self.removeRenderedFiles(for: previous, vaultURL: vaultURL)
                }
                try self.write(planned: planned, rendered: rendered, vaultURL: vaultURL)
                try stateStore.upsert(self.makeState(from: planned, rendered: rendered, seenAt: now))
                switch pending.kind {
                case .create:
                    summary.createdCount += 1
                    logger.info("created \(planned.noteRelativePath)")
                case .update:
                    summary.updatedCount += 1
                    logger.info("updated \(planned.noteRelativePath)")
                case .move:
                    summary.movedCount += 1
                    logger.info("moved \(pending.previous?.noteRelativePath ?? planned.noteRelativePath) -> \(planned.noteRelativePath)")
                }
                summary.warningCount += rendered.warnings.count
                pendingByID.removeValue(forKey: note.appleNoteID)
            } catch {
                summary.errorCount += 1
                logger.error(error.localizedDescription)
            }
        }
        if !pendingByID.isEmpty {
            summary.errorCount += pendingByID.count
            for pending in pendingByID.values.sorted(by: { $0.noteRelativePath < $1.noteRelativePath }) {
                logger.error("detail fetch missing for \(pending.noteRelativePath)")
            }
        }

        summary.duration = Date().timeIntervalSince(startedAt)
        logger.info(
            "run finished: created=\(summary.createdCount) updated=\(summary.updatedCount) moved=\(summary.movedCount) deleted=\(summary.deletedCount) warnings=\(summary.warningCount) errors=\(summary.errorCount)"
        )
        return summary
    }

    private static func baseName(from relativePath: String) -> String {
        ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private func write(planned: PlannedNote, rendered: RenderedNote, vaultURL: URL) throws {
        let markdownURL = vaultURL.appendingPathComponent(planned.noteRelativePath)
        try fileManager.createDirectory(at: markdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let assetDirURL = vaultURL.appendingPathComponent(planned.assetRelativeDir, isDirectory: true)
        try recreateDirectory(at: assetDirURL)

        for asset in rendered.assets {
            let target = vaultURL.appendingPathComponent(asset.relativePath)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try asset.data.write(to: target, options: .atomic)
        }

        let tempURL = markdownURL.appendingPathExtension("tmp")
        try Data(rendered.markdown.utf8).write(to: tempURL, options: .atomic)
        if fileManager.fileExists(atPath: markdownURL.path) {
            try fileManager.removeItem(at: markdownURL)
        }
        try fileManager.moveItem(at: tempURL, to: markdownURL)
    }

    private func recreateDirectory(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func removeRenderedFiles(for state: ManagedNoteState, vaultURL: URL) throws {
        let markdownURL = vaultURL.appendingPathComponent(state.noteRelativePath)
        if fileManager.fileExists(atPath: markdownURL.path) {
            try fileManager.removeItem(at: markdownURL)
        }
        let assetURL = vaultURL.appendingPathComponent(state.assetRelativeDir)
        if fileManager.fileExists(atPath: assetURL.path) {
            try fileManager.removeItem(at: assetURL)
        }
    }

    private func makeState(from planned: PlannedNote, rendered: RenderedNote, seenAt: String) -> ManagedNoteState {
        ManagedNoteState(
            appleNoteID: planned.note.appleNoteID,
            createdAt: SyncPlanner.isoString(planned.note.createdAt),
            updatedAt: SyncPlanner.isoString(planned.note.updatedAt),
            sourceFolderPath: planned.note.folderPath,
            noteRelativePath: planned.noteRelativePath,
            assetRelativeDir: planned.assetRelativeDir,
            contentHash: rendered.contentHash,
            assetManifestHash: rendered.assetManifestHash,
            lastSeenAt: seenAt,
            missingScanCount: 0,
            isDeleted: false
        )
    }
}

private extension PendingSyncKind {
    var logLabel: String {
        switch self {
        case .create: return "create"
        case .update: return "update"
        case .move: return "move"
        }
    }
}
