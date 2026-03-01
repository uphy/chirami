import Foundation
import Testing
import Yams
@testable import Chirami

@Suite("NoteConfig.resolveAttachmentsDir")
struct AttachmentsDirTests {

    // MARK: - Fallback (no config set)

    @Test("static note fallback: <note-stem>.attachments/")
    func staticNoteFallback() {
        let config = NoteConfig(path: "~/notes/todo.md")
        let noteURL = URL(fileURLWithPath: "/Users/test/notes/todo.md")
        let result = config.resolveAttachmentsDir(noteURL: noteURL, isPeriodicNote: false, pathTemplate: nil)
        #expect(result.path == "/Users/test/notes/todo.attachments")
    }

    @Test("periodic note fallback: template parent + attachments/")
    func periodicNoteFallback() {
        let config = NoteConfig(path: "/Users/test/notes/daily/{yyyy-MM-dd}.md")
        let noteURL = URL(fileURLWithPath: "/Users/test/notes/daily/2026-02-26.md")
        let result = config.resolveAttachmentsDir(noteURL: noteURL, isPeriodicNote: true, pathTemplate: "/Users/test/notes/daily/{yyyy-MM-dd}.md")
        #expect(result.path == "/Users/test/notes/daily/attachments")
    }

    // MARK: - Note-level config

    @Test("note-level relative path resolves from note parent")
    func noteRelativePath() {
        let config = NoteConfig(path: "~/notes/todo.md", attachment: AttachmentConfig(dir: "images/"))
        let noteURL = URL(fileURLWithPath: "/Users/test/notes/todo.md")
        let result = config.resolveAttachmentsDir(noteURL: noteURL, isPeriodicNote: false, pathTemplate: nil)
        #expect(result.path == "/Users/test/notes/images")
    }

    @Test("note-level absolute path used as-is")
    func noteAbsolutePath() {
        let config = NoteConfig(path: "~/notes/todo.md", attachment: AttachmentConfig(dir: "/tmp/attachments"))
        let noteURL = URL(fileURLWithPath: "/Users/test/notes/todo.md")
        let result = config.resolveAttachmentsDir(noteURL: noteURL, isPeriodicNote: false, pathTemplate: nil)
        #expect(result.path == "/tmp/attachments")
    }

    @Test("note-level tilde path expands home directory")
    func noteTildePath() {
        let config = NoteConfig(path: "~/notes/todo.md", attachment: AttachmentConfig(dir: "~/Pictures/chirami"))
        let noteURL = URL(fileURLWithPath: "/Users/test/notes/todo.md")
        let result = config.resolveAttachmentsDir(noteURL: noteURL, isPeriodicNote: false, pathTemplate: nil)
        let home = FileManager.realHomeDirectory.path
        #expect(result.path == "\(home)/Pictures/chirami")
    }

    // MARK: - Codable

    @Test("NoteConfig decodes attachment.dir")
    func noteConfigCodable() throws {
        let yaml = """
        path: ~/notes/todo.md
        attachment:
          dir: attachments/
        """
        let config = try YAMLDecoder().decode(NoteConfig.self, from: yaml)
        #expect(config.attachment?.dir == "attachments/")
    }
}
