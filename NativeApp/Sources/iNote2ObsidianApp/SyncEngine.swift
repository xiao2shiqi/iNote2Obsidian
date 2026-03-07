import Foundation

struct SyncPlanner {
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
        let notes = try snapshotProvider.fetchSnapshot()
        let existingStates = try stateStore.fetchStates()
        let actions = planner.plan(notes: notes, existingStates: existingStates, settings: settings)
        let now = SyncPlanner.isoString(Date())

        var summary = SyncRunSummary(
            scannedCount: notes.count,
            createdCount: 0,
            updatedCount: 0,
            movedCount: 0,
            deletedCount: 0,
            warningCount: 0,
            errorCount: 0,
            duration: 0
        )

        logger.info("scan complete: \(notes.count) notes")

        for action in actions {
            do {
                switch action {
                case .create(let planned):
                    let rendered = renderer.render(
                        note: planned.note,
                        stableBaseName: planned.stableBaseName,
                        noteRelativePath: planned.noteRelativePath,
                        assetRelativeDir: planned.assetRelativeDir
                    )
                    try write(planned: planned, rendered: rendered, vaultURL: vaultURL)
                    try stateStore.upsert(makeState(from: planned, rendered: rendered, seenAt: now))
                    logger.info("created \(planned.noteRelativePath)")
                    summary.createdCount += 1
                    summary.warningCount += rendered.warnings.count
                case .update(let planned, _):
                    let rendered = renderer.render(
                        note: planned.note,
                        stableBaseName: planned.stableBaseName,
                        noteRelativePath: planned.noteRelativePath,
                        assetRelativeDir: planned.assetRelativeDir
                    )
                    try write(planned: planned, rendered: rendered, vaultURL: vaultURL)
                    try stateStore.upsert(makeState(from: planned, rendered: rendered, seenAt: now))
                    logger.info("updated \(planned.noteRelativePath)")
                    summary.updatedCount += 1
                    summary.warningCount += rendered.warnings.count
                case .move(let planned, let previous):
                    let rendered = renderer.render(
                        note: planned.note,
                        stableBaseName: planned.stableBaseName,
                        noteRelativePath: planned.noteRelativePath,
                        assetRelativeDir: planned.assetRelativeDir
                    )
                    try removeRenderedFiles(for: previous, vaultURL: vaultURL)
                    try write(planned: planned, rendered: rendered, vaultURL: vaultURL)
                    try stateStore.upsert(makeState(from: planned, rendered: rendered, seenAt: now))
                    logger.info("moved \(previous.noteRelativePath) -> \(planned.noteRelativePath)")
                    summary.movedCount += 1
                    summary.warningCount += rendered.warnings.count
                case .delete(let previous):
                    try removeRenderedFiles(for: previous, vaultURL: vaultURL)
                    var state = previous
                    state.isDeleted = true
                    state.missingScanCount = 2
                    state.lastSeenAt = now
                    try stateStore.upsert(state)
                    logger.info("deleted \(previous.noteRelativePath)")
                    summary.deletedCount += 1
                case .markMissing(let previous, let nextMissingCount):
                    var state = previous
                    state.missingScanCount = nextMissingCount
                    state.lastSeenAt = now
                    try stateStore.upsert(state)
                    logger.info("missing once \(previous.noteRelativePath)")
                case .noop(let planned, let previous):
                    var state = previous
                    state.updatedAt = SyncPlanner.isoString(planned.note.updatedAt)
                    state.sourceFolderPath = planned.note.folderPath
                    state.lastSeenAt = now
                    state.missingScanCount = 0
                    state.isDeleted = false
                    try stateStore.upsert(state)
                }
            } catch {
                summary.errorCount += 1
                logger.error(error.localizedDescription)
            }
        }

        summary.duration = Date().timeIntervalSince(startedAt)
        logger.info(
            "run finished: created=\(summary.createdCount) updated=\(summary.updatedCount) moved=\(summary.movedCount) deleted=\(summary.deletedCount) warnings=\(summary.warningCount) errors=\(summary.errorCount)"
        )
        return summary
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
