import Foundation
import Testing
@testable import Chirami

@Suite("AttachmentCleanupService")
struct AttachmentCleanupServiceTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chirami-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeNote(path: URL, attachmentsDir: URL) -> Note {
        Note(
            id: "test-\(UUID().uuidString)",
            path: path,
            title: "Test",
            color: .yellow,
            attachmentsDir: attachmentsDir
        )
    }

    // MARK: - extractImagePaths

    @Test("extracts image paths from markdown content")
    func extractImagePaths() {
        let content = """
        Some text
        ![](attachments/image-abc123.png)
        More text
        ![alt text](images/photo.png)
        ![](../other/image-def456.png)
        """
        let paths = AttachmentCleanupService.extractImagePaths(from: content)
        #expect(paths == [
            "attachments/image-abc123.png",
            "images/photo.png",
            "../other/image-def456.png",
        ])
    }

    @Test("returns empty array for content with no images")
    func extractImagePathsEmpty() {
        let content = "Just some text\nNo images here"
        let paths = AttachmentCleanupService.extractImagePaths(from: content)
        #expect(paths.isEmpty)
    }

    @Test("handles links that are not images")
    func extractImagePathsIgnoresLinks() {
        let content = "[link text](http://example.com)"
        let paths = AttachmentCleanupService.extractImagePaths(from: content)
        #expect(paths.isEmpty)
    }

    // MARK: - cleanupOrphanedAttachments

    @Test("referenced images are not deleted")
    func referencedImagesKept() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let attachmentsDir = tempDir.appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        // Create an image file
        let imageFile = attachmentsDir.appendingPathComponent("image-abc123.png")
        try Data([0x89, 0x50]).write(to: imageFile)

        // Create a note that references the image
        let noteFile = tempDir.appendingPathComponent("note.md")
        try "![](attachments/image-abc123.png)".write(to: noteFile, atomically: true, encoding: .utf8)

        let note = makeNote(path: noteFile, attachmentsDir: attachmentsDir)
        AttachmentCleanupService.cleanupOrphanedAttachments(notes: [note])

        #expect(FileManager.default.fileExists(atPath: imageFile.path))
    }

    @Test("unreferenced images are deleted")
    func unreferencedImagesDeleted() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let attachmentsDir = tempDir.appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        // Create an orphaned image file
        let orphanedImage = attachmentsDir.appendingPathComponent("image-orphan123.png")
        try Data([0x89, 0x50]).write(to: orphanedImage)

        // Create a note that does NOT reference the image
        let noteFile = tempDir.appendingPathComponent("note.md")
        try "Some text without images".write(to: noteFile, atomically: true, encoding: .utf8)

        let note = makeNote(path: noteFile, attachmentsDir: attachmentsDir)
        AttachmentCleanupService.cleanupOrphanedAttachments(notes: [note])

        #expect(!FileManager.default.fileExists(atPath: orphanedImage.path))
    }

    @Test("non image-*.png files are not deleted")
    func nonImageFilesKept() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let attachmentsDir = tempDir.appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        // Create files that don't match image-*.png pattern
        let textFile = attachmentsDir.appendingPathComponent("notes.txt")
        try "hello".write(to: textFile, atomically: true, encoding: .utf8)

        let otherPng = attachmentsDir.appendingPathComponent("photo.png")
        try Data([0x89, 0x50]).write(to: otherPng)

        // Create a note with no image references
        let noteFile = tempDir.appendingPathComponent("note.md")
        try "No images".write(to: noteFile, atomically: true, encoding: .utf8)

        let note = makeNote(path: noteFile, attachmentsDir: attachmentsDir)
        AttachmentCleanupService.cleanupOrphanedAttachments(notes: [note])

        // Non image-* files should still exist
        #expect(FileManager.default.fileExists(atPath: textFile.path))
        #expect(FileManager.default.fileExists(atPath: otherPng.path))
    }

    @Test("skips when attachmentsDir does not exist")
    func skipsNonExistentDir() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let attachmentsDir = tempDir.appendingPathComponent("nonexistent")
        let noteFile = tempDir.appendingPathComponent("note.md")
        try "text".write(to: noteFile, atomically: true, encoding: .utf8)

        let note = makeNote(path: noteFile, attachmentsDir: attachmentsDir)

        // Should not crash or throw
        AttachmentCleanupService.cleanupOrphanedAttachments(notes: [note])
    }

    @Test("mixed: keeps referenced, deletes unreferenced")
    func mixedReferencedAndUnreferenced() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let attachmentsDir = tempDir.appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        // Create referenced and unreferenced images
        let referencedImage = attachmentsDir.appendingPathComponent("image-referenced.png")
        try Data([0x89, 0x50]).write(to: referencedImage)

        let orphanedImage = attachmentsDir.appendingPathComponent("image-orphaned.png")
        try Data([0x89, 0x50]).write(to: orphanedImage)

        let noteFile = tempDir.appendingPathComponent("note.md")
        try "![](attachments/image-referenced.png)".write(to: noteFile, atomically: true, encoding: .utf8)

        let note = makeNote(path: noteFile, attachmentsDir: attachmentsDir)
        AttachmentCleanupService.cleanupOrphanedAttachments(notes: [note])

        #expect(FileManager.default.fileExists(atPath: referencedImage.path))
        #expect(!FileManager.default.fileExists(atPath: orphanedImage.path))
    }
}
