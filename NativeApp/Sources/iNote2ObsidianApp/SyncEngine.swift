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
        var updated = 0
        var skipped = 0
        var deleted = 0
        var errors = 0
        var scanned = 0
        var matched = 0
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
                matched: 0,
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

        let totalFromHeaders = try bridge.streamNoteHeaders(
            excludeRecentlyDeleted: settings.excludeRecentlyDeleted,
            cancellation: cancellation,
            onHeader: { [self] header in
                if cancellation.isCancelled {
                    return
                }
                scanned += 1
                seenSourceIDs.insert(header.noteID)

                if self.canTreatAsMatched(header: header, stateStore: stateStore, existingIndex: existingIndex) {
                    skipped += 1
                    matched += 1
                    progress?(
                        SyncProgress(
                            stage: .noteProcessed,
                            total: total,
                            totalKnown: totalKnown,
                            scanned: scanned,
                            matched: matched,
                            pending: max(scanned - matched, 0),
                            currentNote: header.title,
                            eventType: .skipped,
                            outputFile: existingIndex.bySourceID[header.noteID]?.relativePath,
                            message: "Matched existing note",
                            queuePreview: []
                        )
                    )
                    return
                }

                if queuePreview.count < 30 {
                    queuePreview.append("\(header.folderPath)/\(header.title)")
                }

                do {
                    guard let note = try bridge.fetchNoteDetails(noteID: header.noteID, cancellation: cancellation) else {
                        errors += 1
                        logger.error("detail fetch returned empty for note: \(header.noteID)")
                        return
                    }
                    self.processNote(
                        note,
                        outputRoot: outputRoot,
                        start: start,
                        existingIndex: existingIndex,
                        stateStore: stateStore,
                        cancellation: cancellation,
                        added: &added,
                        updated: &updated,
                        skipped: &skipped,
                        errors: &errors,
                        matched: &matched,
                        queuePreview: &queuePreview,
                        total: total,
                        totalKnown: totalKnown,
                        scanned: scanned,
                        progress: progress
                    )
                } catch {
                    errors += 1
                    logger.error("detail fetch failed for \(header.noteID): \(error.localizedDescription)")
                }
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
                        matched: matched,
                        pending: max(bridgeProgress.scannedCount - matched, 0),
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

        total = max(totalFromHeaders, scanned)
        totalKnown = true
        progress?(
            SyncProgress(
                stage: .queueReady,
                total: total,
                totalKnown: true,
                scanned: scanned,
                matched: matched,
                pending: max(total - matched, 0),
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
            if let st = try stateStore.getNoteState(noteID: id) {
                deleteMirroredNote(outputRoot: outputRoot, markdownRelativePath: st.markdownRelativePath)
            }
            try stateStore.markDeleted(noteID: id)
        }

        let status: SyncStatus = errors == 0 ? .success : .failedRuntime
        logger.info("sync finished added=\(added) updated=\(updated) skipped=\(skipped) deleted=\(deleted) errors=\(errors)")
        progress?(
            SyncProgress(
                stage: .completed,
                total: total,
                totalKnown: true,
                scanned: scanned,
                matched: matched,
                pending: max(total - matched, 0),
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

    private func canTreatAsMatched(
        header: SourceNoteHeader,
        stateStore: StateStore,
        existingIndex: ExistingNoteIndex
    ) -> Bool {
        guard let previous = try? stateStore.getNoteState(noteID: header.noteID) else {
            return false
        }
        guard
            !previous.isDeleted,
            previous.sourceUpdatedAt == isoString(header.updatedAt),
            let existing = existingIndex.bySourceID[header.noteID],
            existing.relativePath == previous.markdownRelativePath,
            existing.contentHash == previous.contentHash,
            existing.exportVersion == MarkdownTransformer.exportVersion
        else {
            return false
        }
        return true
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func deleteMirroredNote(outputRoot: URL, markdownRelativePath: String) {
        let url = outputRoot.appendingPathComponent(markdownRelativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
        cleanupEmptyParentDirectories(from: url.deletingLastPathComponent(), stopAt: outputRoot)
    }

    private func cleanupEmptyParentDirectories(from start: URL, stopAt root: URL) {
        let fm = FileManager.default
        var current = start.standardizedFileURL
        let stop = root.standardizedFileURL

        while current.path.hasPrefix(stop.path), current != stop {
            let children = (try? fm.contentsOfDirectory(at: current, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            if !children.isEmpty {
                break
            }
            try? fm.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }

    private func processNote(
        _ note: SourceNote,
        outputRoot: URL,
        start: Date,
        existingIndex: ExistingNoteIndex,
        stateStore: StateStore,
        cancellation: SyncCancellationController,
        added: inout Int,
        updated: inout Int,
        skipped: inout Int,
        errors: inout Int,
        matched: inout Int,
        queuePreview: inout [String],
        total: Int,
        totalKnown: Bool,
        scanned: Int,
        progress: ((SyncProgress) -> Void)?
    ) {
        if cancellation.isCancelled {
            return
        }

        let contentHash = transformer.bodyHash(for: note)

        if
            let existing = existingIndex.bySourceID[note.noteID],
            existing.contentHash == contentHash,
            existing.exportVersion == MarkdownTransformer.exportVersion
        {
            do {
                try stateStore.upsertNoteState(
                    noteID: note.noteID,
                    folderPath: note.folderPath,
                    sourceUpdatedAt: isoString(note.updatedAt),
                    contentHash: contentHash,
                    markdownRelativePath: existing.relativePath,
                    isDeleted: false
                )
                skipped += 1
                matched += 1
                emitProgress(
                    stage: .noteProcessed,
                    total: total,
                    totalKnown: totalKnown,
                    scanned: scanned,
                    matched: matched,
                    pending: max(scanned - matched, 0),
                    note: note.title,
                    event: .skipped,
                    outputFile: existing.relativePath,
                    message: "Matched existing note",
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
                    matched: matched,
                    pending: max(scanned - matched, 0),
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
            let relativePath: String
            if let existing = existingIndex.bySourceID[note.noteID] {
                relativePath = existing.relativePath
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
                sourceUpdatedAt: isoString(note.updatedAt),
                contentHash: contentHash,
                markdownRelativePath: relativePath,
                isDeleted: false
            )

            let wasExisting = existingIndex.bySourceID[note.noteID] != nil
            if wasExisting {
                updated += 1
            } else {
                added += 1
            }
            matched += 1
            if !queuePreview.contains("\(note.folderPath)/\(note.title)") && queuePreview.count < 30 {
                queuePreview.append("\(note.folderPath)/\(note.title)")
            }
            emitProgress(
                stage: .noteProcessed,
                total: total,
                totalKnown: totalKnown,
                scanned: scanned,
                matched: matched,
                pending: max(scanned - matched, 0),
                note: note.title,
                event: wasExisting ? .updated : .added,
                outputFile: relativePath,
                message: wasExisting ? "Updated note" : "Added note",
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
                matched: matched,
                pending: max(scanned - matched, 0),
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
        matched: Int,
        pending: Int,
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
                matched: matched,
                pending: pending,
                currentNote: note,
                eventType: event,
                outputFile: outputFile,
                message: message,
                queuePreview: []
            )
        )
    }
}
