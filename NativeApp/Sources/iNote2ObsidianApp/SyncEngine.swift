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
        cancellation: SyncCancellationController = SyncCancellationController(),
        progress: ((SyncProgress) -> Void)? = nil
    ) throws -> SyncRunStats {
        let start = Date()
        logger.info("sync started")

        var added = 0
        let updated = 0
        var skipped = 0
        var deleted = 0
        var errors = 0
        var scanned = 0
        var synced = 0
        var seenSourceIDs = Set<String>()
        var queuePreview: [String] = []
        var totalKnown = false
        var total = 0

        progress?(
            SyncProgress(
                stage: .fetching,
                total: 0,
                totalKnown: false,
                scanned: 0,
                synced: 0,
                pending: 0,
                currentNote: nil,
                eventType: nil,
                outputFile: nil,
                message: "Fetching notes from Apple Notes (streaming)...",
                queuePreview: []
            )
        )

        let outputRoot = URL(fileURLWithPath: settings.managedOutputRootPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let existingIndex = ExistingNoteIndex.build(outputRoot: outputRoot, logger: logger)

        let bridgeSummary = try bridge.streamNotes(
            excludeRecentlyDeleted: settings.excludeRecentlyDeleted,
            cancellation: cancellation,
            onNote: { [self] note in
                if cancellation.isCancelled {
                    return
                }
                scanned += 1
                seenSourceIDs.insert(note.noteID)

                if queuePreview.count < 30 {
                    queuePreview.append("\(note.folderPath)/\(note.title)")
                }

                self.processNote(
                    note,
                    outputRoot: outputRoot,
                    start: start,
                    existingIndex: existingIndex,
                    stateStore: stateStore,
                    cancellation: cancellation,
                    added: &added,
                    skipped: &skipped,
                    errors: &errors,
                    synced: &synced,
                    total: total,
                    totalKnown: totalKnown,
                    scanned: scanned,
                    progress: progress
                )
            },
            onProgress: { bridgeProgress in
                if cancellation.isCancelled {
                    return
                }
                progress?(
                    SyncProgress(
                        stage: .fetching,
                        total: total,
                        totalKnown: false,
                        scanned: bridgeProgress.scannedCount,
                        synced: synced,
                        pending: 0,
                        currentNote: nil,
                        eventType: nil,
                        outputFile: nil,
                        message: "SCANNED:\(bridgeProgress.scannedCount)",
                        queuePreview: []
                    )
                )
            }
        )

        if cancellation.isCancelled {
            throw SyncError.cancelled
        }

        total = max(bridgeSummary.totalNotes, scanned)
        totalKnown = true

        for failed in bridgeSummary.failedNotes {
            if cancellation.isCancelled {
                throw SyncError.cancelled
            }
            logger.info("retrying failed streamed note: \(failed.noteID)")
            do {
                guard let note = try bridge.fetchNoteDetails(noteID: failed.noteID, cancellation: cancellation) else {
                    errors += 1
                    logger.error("fallback fetch returned empty for note: \(failed.noteID)")
                    continue
                }
                seenSourceIDs.insert(note.noteID)
                processNote(
                    note,
                    outputRoot: outputRoot,
                    start: start,
                    existingIndex: existingIndex,
                    stateStore: stateStore,
                    cancellation: cancellation,
                    added: &added,
                    skipped: &skipped,
                    errors: &errors,
                    synced: &synced,
                    total: total,
                    totalKnown: totalKnown,
                    scanned: scanned,
                    progress: progress
                )
            } catch {
                errors += 1
                logger.error("fallback note retry failed for \(failed.noteID): \(error.localizedDescription)")
            }
        }
        progress?(
            SyncProgress(
                stage: .queueReady,
                total: total,
                totalKnown: true,
                scanned: scanned,
                synced: synced,
                pending: max(total - synced, 0),
                currentNote: nil,
                eventType: nil,
                outputFile: nil,
                message: "Queue ready",
                queuePreview: queuePreview
            )
        )

        let existing = try stateStore.existingNoteIDs()
        for id in existing where !seenSourceIDs.contains(id) {
            if cancellation.isCancelled {
                throw SyncError.cancelled
            }
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
                totalKnown: true,
                scanned: scanned,
                synced: synced,
                pending: max(total - synced, 0),
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
        return ExistingNoteIndex.extractSourceNoteID(fromMarkdown: text)
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

    private func processNote(
        _ note: SourceNote,
        outputRoot: URL,
        start: Date,
        existingIndex: ExistingNoteIndex,
        stateStore: StateStore,
        cancellation: SyncCancellationController,
        added: inout Int,
        skipped: inout Int,
        errors: inout Int,
        synced: inout Int,
        total: Int,
        totalKnown: Bool,
        scanned: Int,
        progress: ((SyncProgress) -> Void)?
    ) {
        if cancellation.isCancelled {
            return
        }

        if let existingRelativePath = existingIndex.bySourceID[note.noteID] {
            do {
                try stateStore.upsertNoteState(
                    noteID: note.noteID,
                    folderPath: note.folderPath,
                    contentHash: "exists-skip",
                    markdownRelativePath: existingRelativePath,
                    isDeleted: false
                )
                skipped += 1
                emitProgress(
                    stage: .noteProcessed,
                    total: total,
                    totalKnown: totalKnown,
                    scanned: scanned,
                    synced: synced,
                    note: note.title,
                    event: .skipped,
                    outputFile: existingRelativePath,
                    message: "Skipped existing note",
                    progress: progress
                )
            } catch {
                errors += 1
                logger.error("note failed while upserting skip state: \(error.localizedDescription)")
                emitProgress(
                    stage: .noteProcessed,
                    total: total,
                    totalKnown: totalKnown,
                    scanned: scanned,
                    synced: synced,
                    note: note.title,
                    event: .failed,
                    outputFile: nil,
                    message: "Failed note: \(error.localizedDescription)",
                    progress: progress
                )
            }
            return
        }

        do {
            let rendered = transformer.render(note: note, outputRoot: outputRoot, runDate: start)
            let relativePath = try resolveUniqueMarkdownPath(
                baseFolder: rendered.folderPath,
                preferredFilename: rendered.preferredMarkdownFilename,
                outputRoot: outputRoot,
                sourceNoteID: rendered.sourceNoteID
            )

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
                contentHash: hash(rendered.markdown),
                markdownRelativePath: relativePath,
                isDeleted: false
            )

            added += 1
            synced += 1
            emitProgress(
                stage: .noteProcessed,
                total: total,
                totalKnown: totalKnown,
                scanned: scanned,
                synced: synced,
                note: note.title,
                event: .added,
                outputFile: relativePath,
                message: "Added note",
                progress: progress
            )
        } catch {
            errors += 1
            logger.error("note failed: \(error.localizedDescription)")
            emitProgress(
                stage: .noteProcessed,
                total: total,
                totalKnown: totalKnown,
                scanned: scanned,
                synced: synced,
                note: note.title,
                event: .failed,
                outputFile: nil,
                message: "Failed note: \(error.localizedDescription)",
                progress: progress
            )
        }
    }

    private func emitProgress(
        stage: SyncProgressStage,
        total: Int,
        totalKnown: Bool,
        scanned: Int,
        synced: Int,
        note: String?,
        event: SyncNoteEventType?,
        outputFile: String?,
        message: String?,
        progress: ((SyncProgress) -> Void)?
    ) {
        progress?(
            SyncProgress(
                stage: stage,
                total: total,
                totalKnown: totalKnown,
                scanned: scanned,
                synced: synced,
                pending: 0,
                currentNote: note,
                eventType: event,
                outputFile: outputFile,
                message: message,
                queuePreview: []
            )
        )
    }
}
