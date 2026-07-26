import Foundation
import Testing
@testable import Chirami

/// Builds a `NoteStore` whose `AppConfig`/`AppState` are rooted in a unique
/// temporary directory. Never use `NoteStore.shared` in tests: it reads and
/// writes the developer's real `~/.config/chirami` / `~/.local/state/chirami`.
@MainActor
private final class NoteStoreFixture {
    let root: URL
    let notesDir: URL
    let appConfig: AppConfig
    let appState: AppState
    let store: NoteStore

    init(configYAML: String? = nil) throws {
        root = try makeTestDirectory()
        notesDir = root.appendingPathComponent("notes", isDirectory: true)
        let configDir = root.appendingPathComponent("config", isDirectory: true)
        let stateDir = root.appendingPathComponent("state", isDirectory: true)

        if let configYAML {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            try configYAML.write(to: configDir.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        }

        appConfig = AppConfig(directory: configDir, createSampleConfigIfNeeded: false, watchForChanges: false)
        appState = AppState(directory: stateDir)
        store = NoteStore(config: appConfig, state: appState)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    return Calendar.current.date(from: components)!
}

@Suite("NoteStore")
@MainActor
struct NoteStoreTests {

    // MARK: - resolvePeriodicNote

    @Test("creates an empty file and parent directories when the note does not exist")
    func periodicNoteCreatesEmptyFile() throws {
        let fixture = try NoteStoreFixture()
        let config = NoteConfig(path: "\(fixture.notesDir.path)/daily/{yyyy-MM-dd}.md")
        let date = makeDate(year: 2026, month: 6, day: 11)

        let note = try #require(fixture.store.resolvePeriodicNote(from: config, for: date))

        let expectedPath = fixture.notesDir.appendingPathComponent("daily/2026-06-11.md").path
        #expect(note.path.path == expectedPath)
        #expect(FileManager.default.fileExists(atPath: expectedPath))
        #expect(try String(contentsOf: note.path, encoding: .utf8) == "")
    }

    @Test("copies the template content when creating a new periodic note")
    func periodicNoteCopiesTemplate() throws {
        let fixture = try NoteStoreFixture()
        let templateURL = fixture.notesDir.appendingPathComponent("template.md")
        try FileManager.default.createDirectory(at: fixture.notesDir, withIntermediateDirectories: true)
        let templateContent = "## Tasks\n\n- [ ] \n"
        try templateContent.write(to: templateURL, atomically: true, encoding: .utf8)

        var config = NoteConfig(path: "\(fixture.notesDir.path)/daily/{yyyy-MM-dd}.md")
        config.template = templateURL.path
        let date = makeDate(year: 2026, month: 6, day: 11)

        let note = try #require(fixture.store.resolvePeriodicNote(from: config, for: date))
        #expect(try String(contentsOf: note.path, encoding: .utf8) == templateContent)
        #expect(note.periodicInfo?.templateFile?.path == templateURL.path)
    }

    @Test("falls back to an empty file when the template is missing")
    func periodicNoteMissingTemplateFallsBack() throws {
        let fixture = try NoteStoreFixture()
        var config = NoteConfig(path: "\(fixture.notesDir.path)/daily/{yyyy-MM-dd}.md")
        config.template = "\(fixture.notesDir.path)/no-such-template.md"
        let date = makeDate(year: 2026, month: 6, day: 11)

        let note = try #require(fixture.store.resolvePeriodicNote(from: config, for: date))
        #expect(FileManager.default.fileExists(atPath: note.path.path))
        #expect(try String(contentsOf: note.path, encoding: .utf8) == "")
    }

    @Test("does not overwrite an existing periodic note file")
    func periodicNoteKeepsExistingContent() throws {
        let fixture = try NoteStoreFixture()
        let dailyDir = fixture.notesDir.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: dailyDir, withIntermediateDirectories: true)
        let existing = "existing content"
        try existing.write(to: dailyDir.appendingPathComponent("2026-06-11.md"), atomically: true, encoding: .utf8)

        let config = NoteConfig(path: "\(fixture.notesDir.path)/daily/{yyyy-MM-dd}.md")
        let date = makeDate(year: 2026, month: 6, day: 11)

        let note = try #require(fixture.store.resolvePeriodicNote(from: config, for: date))
        #expect(try String(contentsOf: note.path, encoding: .utf8) == existing)
    }

    @Test("builds title as 'configTitle — fileName' when a title is configured")
    func periodicNoteTitleWithPrefix() throws {
        let fixture = try NoteStoreFixture()
        var config = NoteConfig(path: "\(fixture.notesDir.path)/daily/{yyyy-MM-dd}.md")
        config.title = "Daily"
        let date = makeDate(year: 2026, month: 6, day: 11)

        let note = try #require(fixture.store.resolvePeriodicNote(from: config, for: date))
        #expect(note.title == "Daily — 2026-06-11")
        #expect(note.periodicInfo?.titlePrefix == "Daily")
    }

    @Test("uses the resolved file name as title when no title is configured")
    func periodicNoteTitleWithoutPrefix() throws {
        let fixture = try NoteStoreFixture()
        let config = NoteConfig(path: "\(fixture.notesDir.path)/daily/{yyyy-MM-dd}.md")
        let date = makeDate(year: 2026, month: 6, day: 11)

        let note = try #require(fixture.store.resolvePeriodicNote(from: config, for: date))
        #expect(note.title == "2026-06-11")
        #expect(note.periodicInfo?.titlePrefix == nil)
    }

    @Test("note id matches the config noteId and periodicInfo carries the template path")
    func periodicNoteIdentityAndInfo() throws {
        let fixture = try NoteStoreFixture()
        let template = "\(fixture.notesDir.path)/daily/{yyyy-MM-dd}.md"
        let config = NoteConfig(path: template)
        let date = makeDate(year: 2026, month: 6, day: 11)

        let note = try #require(fixture.store.resolvePeriodicNote(from: config, for: date))
        #expect(note.id == config.noteId)
        #expect(note.periodicInfo?.pathTemplate == template)
    }

    @Test("preserves appearance attributes from the original config")
    func periodicNotePreservesAttributes() throws {
        let fixture = try NoteStoreFixture()
        var config = NoteConfig(path: "\(fixture.notesDir.path)/daily/{yyyy-MM-dd}.md")
        config.theme = "dark"
        config.transparency = 0.5
        config.alwaysOnTop = false
        config.hotkeys = [HotkeyBinding(key: "option+d", action: .toggle)]
        let date = makeDate(year: 2026, month: 6, day: 11)

        let note = try #require(fixture.store.resolvePeriodicNote(from: config, for: date))
        #expect(note.theme == "dark")
        #expect(note.transparency == 0.5)
        #expect(note.alwaysOnTop == false)
        #expect(note.hotkeys.count == 1)
    }

    // MARK: - loadFromConfig / noteConfig

    @Test("loads notes from config.yaml in the injected directory")
    func loadsNotesFromInjectedConfig() throws {
        let fixture = try NoteStoreFixture()
        fixture.appConfig.update { config in
            config.notes = [NoteConfig(path: "\(fixture.notesDir.path)/todo.md", title: "TODO")]
        }
        fixture.store.loadFromConfig()

        #expect(fixture.store.notes.count == 1)
        #expect(fixture.store.notes.first?.title == "TODO")
    }

    @Test("noteConfig(for:) returns the original config with all attributes")
    func noteConfigLookup() throws {
        let fixture = try NoteStoreFixture()
        var config = NoteConfig(path: "\(fixture.notesDir.path)/daily/{yyyy-MM-dd}.md", title: "Daily")
        config.theme = "dark"
        config.rolloverDelay = "3h"
        fixture.appConfig.update { $0.notes = [config] }

        let found = try #require(fixture.store.noteConfig(for: config.noteId))
        #expect(found.theme == "dark")
        #expect(found.rolloverDelay == "3h")
        #expect(found.title == "Daily")
    }

    @Test("noteConfig(for:) returns nil for an unknown noteId")
    func noteConfigLookupUnknown() throws {
        let fixture = try NoteStoreFixture()
        #expect(fixture.store.noteConfig(for: "deadbeef0000") == nil)
    }

    // MARK: - Window state via injected AppState

    @Test("window state round-trips through the injected AppState")
    func windowStatePersistsToInjectedState() throws {
        let fixture = try NoteStoreFixture()
        let config = NoteConfig(path: "\(fixture.notesDir.path)/daily/{yyyy-MM-dd}.md")
        let date = makeDate(year: 2026, month: 6, day: 11)
        let note = try #require(fixture.store.resolvePeriodicNote(from: config, for: date))

        fixture.store.saveWindowState(
            for: note,
            position: CGPoint(x: 10, y: 20),
            size: CGSize(width: 300, height: 400),
            visible: true
        )

        let ws = try #require(fixture.store.windowState(for: note))
        #expect(ws.position == [10, 20])
        #expect(ws.size == [300, 400])
        #expect(ws.visible == true)

        // Persisted inside the fixture's tmpdir, not the real state dir
        let stateFile = fixture.root.appendingPathComponent("state/state.yaml")
        #expect(FileManager.default.fileExists(atPath: stateFile.path))
    }
}
