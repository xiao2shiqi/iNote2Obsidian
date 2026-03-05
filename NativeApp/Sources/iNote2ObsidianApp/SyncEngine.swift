import Foundation

final class SyncEngine {
    private let bridge: NotesBridge
    private let transformer = MarkdownTransformer()
    private let logger: AppLogger

    init(bridge: NotesBridge, logger: AppLogger) {
        self.bridge = bridge
        self.logger = logger
    }

    func run(
        settings: AppSettings,
        stateStore: StateStore,
        progress: ((SyncProgress) -> Void)? = nil
    ) throws -> SyncRunStats {
        let start = Date()
        logger.info("sync started")
        var added = 0
        var updated = 0
        var skipped = 0
        var deleted = 0
        var errors = 0
        let notes: [SourceNote]

        do {
            notes = try bridge.fetchNotes(excludeRecentlyDeleted: settings.excludeRecentlyDeleted)
        } catch let err as SyncError {
            switch err {
            case .permissionDenied:
                throw err
            default:
                throw err
            }
        }

        let outputRoot = URL(fileURLWithPath: settings.outputRootPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        let noteIDs = Set(notes.map(\.noteID))
        let total = notes.count
        var processed = 0

        progress?(
            SyncProgress(
                stage: .queueReady,
                total: total,
                processed: 0,
                pending: total,
                currentNote: nil,
                eventType: nil,
                outputFile: nil,
                message: "Queue ready",
                queuePreview: notes.prefix(30).map { "\($0.folderPath)/\($0.title)" }
            )
        )

        for note in notes {
            do {
                let rendered = transformer.render(note: note, outputRoot: outputRoot, runDate: start)
                let contentHash = hash(rendered.markdown)
                let prev = try stateStore.getNoteState(noteID: note.noteID)

                if let prev, prev.contentHash == contentHash, !prev.isDeleted {
                    skipped += 1
                    processed += 1
                    progress?(
                        SyncProgress(
                            stage: .noteProcessed,
                            total: total,
                            processed: processed,
                            pending: max(total - processed, 0),
                            currentNote: note.title,
                            eventType: .skipped,
                            outputFile: prev.markdownRelativePath,
                            message: "Skipped unchanged note",
                            queuePreview: []
                        )
                    )
                    continue
                }

                let relativePath: String
                if let prev {
                    relativePath = prev.markdownRelativePath
                } else {
                    relativePath = try resolveUniqueMarkdownPath(
                        baseFolder: rendered.folderPath,
                        preferredFilename: rendered.preferredMarkdownFilename,
                        outputRoot: outputRoot,
                        sourceNoteID: rendered.sourceNoteID
                    )
                }

                let markdownURL = outputRoot.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(at: markdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let markdownData = rendered.markdown.data(using: .utf8) else {
                    throw SyncError.io("unable to encode markdown")
                }
                try markdownData.write(to: markdownURL, options: .atomic)

                for attachment in rendered.attachments {
                    let attachmentURL = outputRoot.appendingPathComponent(attachment.relativePath)
                    try FileManager.default.createDirectory(at: attachmentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try attachment.data.write(to: attachmentURL, options: .atomic)
                }

                try stateStore.upsertNoteState(
                    noteID: note.noteID,
                    folderPath: rendered.folderPath,
                    contentHash: contentHash,
                    markdownRelativePath: relativePath,
                    isDeleted: false
                )

                if prev == nil {
                    added += 1
                    processed += 1
                    progress?(
                        SyncProgress(
                            stage: .noteProcessed,
                            total: total,
                            processed: processed,
                            pending: max(total - processed, 0),
                            currentNote: note.title,
                            eventType: .added,
                            outputFile: relativePath,
                            message: "Added note",
                            queuePreview: []
                        )
                    )
                } else {
                    updated += 1
                    processed += 1
                    progress?(
                        SyncProgress(
                            stage: .noteProcessed,
                            total: total,
                            processed: processed,
                            pending: max(total - processed, 0),
                            currentNote: note.title,
                            eventType: .updated,
                            outputFile: relativePath,
                            message: "Updated note",
                            queuePreview: []
                        )
                    )
                }
            } catch {
                errors += 1
                logger.error("note failed: \(error.localizedDescription)")
                processed += 1
                progress?(
                    SyncProgress(
                        stage: .noteProcessed,
                        total: total,
                        processed: processed,
                        pending: max(total - processed, 0),
                        currentNote: note.title,
                        eventType: .failed,
                        outputFile: nil,
                        message: "Failed note: \(error.localizedDescription)",
                        queuePreview: []
                    )
                )
            }
        }

        let existing = try stateStore.existingNoteIDs()
        for id in existing where !noteIDs.contains(id) {
            deleted += 1
            try stateStore.markDeleted(noteID: id)
            if let st = try stateStore.getNoteState(noteID: id) {
                markDeletedInFile(outputRoot: outputRoot, markdownRelativePath: st.markdownRelativePath)
            }
        }

        let status: SyncStatus = errors == 0 ? .success : .failedRuntime
        logger.info("sync finished added=\(added) updated=\(updated) skipped=\(skipped) deleted=\(deleted) errors=\(errors)")
        progress?(
            SyncProgress(
                stage: .completed,
                total: total,
                processed: processed,
                pending: max(total - processed, 0),
                currentNote: nil,
                eventType: nil,
                outputFile: nil,
                message: "Run completed",
                queuePreview: []
            )
        )
        return SyncRunStats(
            startedAt: start,
            endedAt: Date(),
            added: added,
            updated: updated,
            skipped: skipped,
            deleted: deleted,
            errors: errors,
            status: status
        )
    }

    private func resolveUniqueMarkdownPath(baseFolder: String, preferredFilename: String, outputRoot: URL, sourceNoteID: String) throws -> String {
        let base = baseFolder.isEmpty ? preferredFilename : baseFolder + "/" + preferredFilename
        let candidate = outputRoot.appendingPathComponent(base)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return base
        }

        if existingSourceID(of: candidate) == sourceNoteID {
            return base
        }

        let filename = (preferredFilename as NSString).deletingPathExtension
        let ext = (preferredFilename as NSString).pathExtension
        for idx in 2...999 {
            let newFilename = filename + "-\(idx)." + ext
            let rel = baseFolder.isEmpty ? newFilename : baseFolder + "/" + newFilename
            let url = outputRoot.appendingPathComponent(rel)
            if !FileManager.default.fileExists(atPath: url.path) || existingSourceID(of: url) == sourceNoteID {
                return rel
            }
        }
        throw SyncError.io("unable to find unique filename")
    }

    private func existingSourceID(of url: URL) -> String? {
        guard let text = try? String(contentsOf: url) else { return nil }
        for line in text.split(separator: "\n") {
            if line.starts(with: "source_note_id:") {
                return String(line.split(separator: ":", maxSplits: 1)[1]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            }
        }
        return nil
    }

    private func markDeletedInFile(outputRoot: URL, markdownRelativePath: String) {
        let url = outputRoot.appendingPathComponent(markdownRelativePath)
        guard var text = try? String(contentsOf: url) else { return }
        if text.contains("is_deleted_in_source: false") {
            text = text.replacingOccurrences(of: "is_deleted_in_source: false", with: "is_deleted_in_source: true")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func hash(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash: UInt64 = 1469598103934665603
        for b in data {
            hash ^= UInt64(b)
            hash = hash &* 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}
