import Foundation
import Testing
@testable import Chirami

@Suite("AppConfig")
struct AppConfigTests {

    @Test("generates sample config and notes inside the injected directory only")
    func sampleInitializationIsDirectoryScoped() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let appConfig = AppConfig(directory: dir, createSampleConfigIfNeeded: true, watchForChanges: false)

        #expect(appConfig.configDirectoryURL == dir)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.yaml").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("sample-notes/welcome.md").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("sample-notes/quick-memo.md").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("sample-notes/daily/template.md").path))
        #expect(appConfig.config.notes.count == 3)
    }

    @Test("does not regenerate samples when config.yaml already exists")
    func existingConfigIsNotOverwritten() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let yaml = """
        notes:
          - path: \(dir.path)/todo.md
            title: TODO
        """
        try yaml.write(to: dir.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)

        let appConfig = AppConfig(directory: dir, createSampleConfigIfNeeded: true, watchForChanges: false)
        #expect(appConfig.config.notes.count == 1)
        #expect(appConfig.config.notes.first?.title == "TODO")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("sample-notes").path))
    }

    @Test("skips sample generation when disabled")
    func sampleGenerationDisabled() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let appConfig = AppConfig(directory: dir, createSampleConfigIfNeeded: false, watchForChanges: false)
        #expect(appConfig.config.notes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.yaml").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("sample-notes").path))
    }

    @Test("corrupt config.yaml is preserved: load fails but save is refused")
    func corruptConfigIsNotOverwritten() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let corrupt = "notes: [unclosed\n  ::: not yaml"
        let configFile = dir.appendingPathComponent("config.yaml")
        try corrupt.write(to: configFile, atomically: true, encoding: .utf8)

        let appConfig = AppConfig(directory: dir, createSampleConfigIfNeeded: true, watchForChanges: false)
        #expect(appConfig.loadFailed)
        #expect(appConfig.config.notes.isEmpty)

        appConfig.update { $0.notes = [] }
        #expect(try String(contentsOf: configFile, encoding: .utf8) == corrupt)
    }
}

@Suite("AppState")
struct AppStateTests {

    @Test("window state round-trips through a fresh instance in the same directory")
    func windowStateRoundTrip() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let state = AppState(directory: dir)
        state.updateWindow(
            for: "note1",
            position: CGPoint(x: 1, y: 2),
            size: CGSize(width: 30, height: 40),
            visible: false
        )

        let reloaded = AppState(directory: dir)
        let ws = try #require(reloaded.windowState(for: "note1"))
        #expect(ws.position == [1, 2])
        #expect(ws.size == [30, 40])
        #expect(ws.visible == false)
    }

    @Test("bookmarks are stored and removed per noteId")
    func bookmarkLifecycle() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let state = AppState(directory: dir)
        let payload = Data([0x01, 0x02, 0x03])
        state.saveBookmark(for: "note1", data: payload)
        #expect(state.bookmarkData(for: "note1") == payload)

        state.removeBookmark(for: "note1")
        #expect(state.bookmarkData(for: "note1") == nil)
    }

    @Test("corrupt state.yaml is preserved: save is refused while loadFailed")
    func corruptStateIsNotOverwritten() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let corrupt = "windows: [unclosed\n  ::: not yaml"
        let stateFile = dir.appendingPathComponent("state.yaml")
        try corrupt.write(to: stateFile, atomically: true, encoding: .utf8)

        let state = AppState(directory: dir)
        #expect(state.loadFailed)

        state.setPinned(true, for: "note1")
        #expect(try String(contentsOf: stateFile, encoding: .utf8) == corrupt)
    }
}
