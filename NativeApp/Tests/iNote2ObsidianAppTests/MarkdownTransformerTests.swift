import Foundation
import XCTest
@testable import iNote2ObsidianApp

final class MarkdownTransformerTests: XCTestCase {
    func testFilenameUsesTimestampFormat() {
        let transformer = MarkdownTransformer()
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 13, minute: 29, second: 48))!
        let note = SourceNote(
            noteID: "id-1",
            title: "T",
            folderPath: "Notes",
            createdAt: date,
            updatedAt: date,
            bodyPlain: "Hello",
            bodyHTML: "",
            inlineAttachments: []
        )

        let rendered = transformer.render(note: note, outputRoot: URL(fileURLWithPath: "/tmp"), runDate: date)
        XCTAssertEqual(rendered.preferredMarkdownFilename, "2026-03-04 13-29-48.md")
    }

    func testAttachmentsUseGlobalRoot() {
        let transformer = MarkdownTransformer()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let note = SourceNote(
            noteID: "id-2",
            title: "T",
            folderPath: "A/B",
            createdAt: date,
            updatedAt: date,
            bodyPlain: "Body",
            bodyHTML: "",
            inlineAttachments: [SourceAttachment(mimeType: "image/png", data: Data([1, 2, 3]))]
        )

        let rendered = transformer.render(note: note, outputRoot: URL(fileURLWithPath: "/tmp"), runDate: date)
        XCTAssertEqual(rendered.attachments.count, 1)
        XCTAssertTrue(rendered.attachments[0].relativePath.starts(with: "attachments/"))
        XCTAssertTrue(rendered.markdown.contains("../../attachments/"))
    }

    func testRenderedMarkdownIncludesStableBodyHash() {
        let transformer = MarkdownTransformer()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let note = SourceNote(
            noteID: "id-3",
            title: "T",
            folderPath: "Notes",
            createdAt: date,
            updatedAt: date,
            bodyPlain: "Hello world",
            bodyHTML: "",
            inlineAttachments: []
        )

        let rendered = transformer.render(note: note, outputRoot: URL(fileURLWithPath: "/tmp"), runDate: date)
        XCTAssertTrue(rendered.markdown.contains("source_content_hash:"))
        XCTAssertEqual(transformer.bodyHash(for: note), "86dfeae555fbfa19")
    }

    func testBodyHashChangesWhenAttachmentChanges() {
        let transformer = MarkdownTransformer()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let noteA = SourceNote(
            noteID: "id-4",
            title: "T",
            folderPath: "Notes",
            createdAt: date,
            updatedAt: date,
            bodyPlain: "Hello world",
            bodyHTML: "",
            inlineAttachments: [SourceAttachment(mimeType: "image/png", data: Data([1, 2, 3]))]
        )
        let noteB = SourceNote(
            noteID: "id-4",
            title: "T",
            folderPath: "Notes",
            createdAt: date,
            updatedAt: date,
            bodyPlain: "Hello world",
            bodyHTML: "",
            inlineAttachments: [SourceAttachment(mimeType: "image/png", data: Data([1, 2, 4]))]
        )

        XCTAssertNotEqual(transformer.bodyHash(for: noteA), transformer.bodyHash(for: noteB))
    }
}
