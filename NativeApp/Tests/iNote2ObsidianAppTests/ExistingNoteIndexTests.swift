import Foundation
import XCTest
@testable import iNote2ObsidianApp

final class ExistingNoteIndexTests: XCTestCase {
    func testExtractSourceNoteIDFromFrontmatter() {
        let markdown = """
        ---
        title: \"hello\"
        source_export_version: 2
        source_note_id: \"note-123\"
        source_content_hash: \"abc123\"
        is_deleted_in_source: false
        ---

        content
        """

        XCTAssertEqual(ExistingNoteIndex.extractSourceNoteID(fromMarkdown: markdown), "note-123")
        XCTAssertEqual(ExistingNoteIndex.extractSourceContentHash(fromMarkdown: markdown), "abc123")
        XCTAssertEqual(ExistingNoteIndex.extractSourceExportVersion(fromMarkdown: markdown), 2)
    }

    func testBuildChoosesNewerFileWhenDuplicateSourceID() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iNote2Obsidian-existing-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let older = root.appendingPathComponent("a.md")
        let newer = root.appendingPathComponent("nested/b.md")
        try FileManager.default.createDirectory(at: newer.deletingLastPathComponent(), withIntermediateDirectories: true)

        let markdown = """
        ---
        source_note_id: dup-id
        ---
        body
        """
        try markdown.write(to: older, atomically: true, encoding: .utf8)
        try markdown.write(to: newer, atomically: true, encoding: .utf8)

        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: newer.path)

        let logger = AppLogger(logURL: root.appendingPathComponent("test.log"))
        let index = ExistingNoteIndex.build(outputRoot: root, logger: logger)
        XCTAssertEqual(index.bySourceID["dup-id"]?.relativePath, "nested/b.md")
    }
}
