import Testing
import AppKit
@testable import Chirami

@Suite("ImagePasteService")
struct ImagePasteServiceTests {

    private func createTestImage(width: Int = 10, height: Int = 10, color: NSColor = .red) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    private func createTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chirami-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - save()

    @Test("saves image as PNG and returns markdown text")
    func saveImageBasic() throws {
        let tempDir = try createTempDir()
        defer { cleanup(tempDir) }

        let attachmentsDir = tempDir.appendingPathComponent("attachments")
        let noteURL = tempDir.appendingPathComponent("note.md")

        let image = createTestImage()
        let service = ImagePasteService()
        let result = try service.save(image: image, to: attachmentsDir, noteURL: noteURL).get()

        // File exists
        #expect(FileManager.default.fileExists(atPath: result.fileURL.path))
        // File is in attachments dir
        #expect(result.fileURL.deletingLastPathComponent().path == attachmentsDir.path)
        // Filename pattern: image-<hash>.png
        #expect(result.fileURL.lastPathComponent.hasPrefix("image-"))
        #expect(result.fileURL.pathExtension == "png")
        // Markdown text contains relative path
        #expect(result.markdownText.hasPrefix("![]("))
        #expect(result.markdownText.hasSuffix(")"))
        #expect(result.markdownText.contains("attachments/image-"))
    }

    @Test("creates directory if not exists")
    func createsDirectory() throws {
        let tempDir = try createTempDir()
        defer { cleanup(tempDir) }

        let attachmentsDir = tempDir.appendingPathComponent("nested/deep/attachments")
        let noteURL = tempDir.appendingPathComponent("note.md")

        let image = createTestImage()
        let service = ImagePasteService()
        let result = try service.save(image: image, to: attachmentsDir, noteURL: noteURL).get()

        #expect(FileManager.default.fileExists(atPath: result.fileURL.path))
    }

    @Test("same image produces same filename (deduplication)")
    func deduplication() throws {
        let tempDir = try createTempDir()
        defer { cleanup(tempDir) }

        let attachmentsDir = tempDir.appendingPathComponent("attachments")
        let noteURL = tempDir.appendingPathComponent("note.md")

        let image = createTestImage()
        let service = ImagePasteService()
        let result1 = try service.save(image: image, to: attachmentsDir, noteURL: noteURL).get()
        let result2 = try service.save(image: image, to: attachmentsDir, noteURL: noteURL).get()

        #expect(result1.fileURL == result2.fileURL)
        #expect(result1.markdownText == result2.markdownText)

        // Only one file should exist
        let files = try FileManager.default.contentsOfDirectory(at: attachmentsDir, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
    }

    @Test("different images produce different filenames")
    func differentImages() throws {
        let tempDir = try createTempDir()
        defer { cleanup(tempDir) }

        let attachmentsDir = tempDir.appendingPathComponent("attachments")
        let noteURL = tempDir.appendingPathComponent("note.md")

        let service = ImagePasteService()
        let result1 = try service.save(image: createTestImage(color: .red), to: attachmentsDir, noteURL: noteURL).get()
        let result2 = try service.save(image: createTestImage(color: .blue), to: attachmentsDir, noteURL: noteURL).get()

        #expect(result1.fileURL != result2.fileURL)
    }

    @Test("relative path calculation works with nested attachments dir")
    func relativePathCalculation() throws {
        let tempDir = try createTempDir()
        defer { cleanup(tempDir) }

        let noteURL = tempDir.appendingPathComponent("notes/project/note.md")
        let attachmentsDir = tempDir.appendingPathComponent("notes/project/note.attachments")

        let image = createTestImage()
        let service = ImagePasteService()
        let result = try service.save(image: image, to: attachmentsDir, noteURL: noteURL).get()

        // Relative path should be note.attachments/image-xxx.png
        #expect(result.markdownText.contains("note.attachments/image-"))
    }
}
