import Foundation
import Testing
@testable import Chirami

private struct StubDocument: Codable, Equatable {
    var name: String = "default"
    var count: Int = 0
}

/// Creates a unique temporary directory so tests never touch the real
/// `~/.config/chirami` / `~/.local/state/chirami`.
func makeTestDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ChiramiTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("YAMLStore")
struct YAMLStoreTests {
    private let fileName = "test.yaml"

    private func makeStore(in directory: URL) -> YAMLStore<StubDocument> {
        YAMLStore(directory: directory, fileName: fileName, label: "Test", defaultValue: StubDocument())
    }

    private func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    @Test("missing file keeps default value and allows save")
    func missingFileKeepsDefault() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(in: dir)
        #expect(store.data == StubDocument())
        #expect(!store.loadFailed)

        store.update { $0.name = "saved" }
        #expect(FileManager.default.fileExists(atPath: fileURL(in: dir).path))
    }

    @Test("loads existing valid YAML")
    func loadsValidYAML() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "name: hello\ncount: 42\n".write(to: fileURL(in: dir), atomically: true, encoding: .utf8)
        let store = makeStore(in: dir)
        #expect(store.data == StubDocument(name: "hello", count: 42))
        #expect(!store.loadFailed)
    }

    @Test("saved value round-trips through a fresh instance")
    func saveRoundTrips() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(in: dir)
        store.update { doc in
            doc.name = "round-trip"
            doc.count = 7
        }

        let reloaded = makeStore(in: dir)
        #expect(reloaded.data == StubDocument(name: "round-trip", count: 7))
    }

    @Test("corrupt YAML keeps default value and sets loadFailed")
    func corruptYAMLKeepsDefault() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "name: [unclosed\n  ::: not yaml".write(to: fileURL(in: dir), atomically: true, encoding: .utf8)
        let store = makeStore(in: dir)
        #expect(store.data == StubDocument())
        #expect(store.loadFailed)
    }

    @Test("save is refused while loadFailed: corrupt file is never overwritten with defaults")
    func saveRefusedAfterLoadFailure() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let corruptContent = "name: [unclosed\n  ::: not yaml"
        try corruptContent.write(to: fileURL(in: dir), atomically: true, encoding: .utf8)
        let store = makeStore(in: dir)
        #expect(store.loadFailed)

        store.save()
        store.update { $0.name = "should not be written" }

        let onDisk = try String(contentsOf: fileURL(in: dir), encoding: .utf8)
        #expect(onDisk == corruptContent)
    }

    @Test("type-mismatched YAML also refuses save")
    func typeMismatchRefusesSave() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Valid YAML, but `count` cannot decode as Int
        let content = "name: ok\ncount: not-a-number\n"
        try content.write(to: fileURL(in: dir), atomically: true, encoding: .utf8)
        let store = makeStore(in: dir)
        #expect(store.loadFailed)

        store.update { $0.count = 1 }
        let onDisk = try String(contentsOf: fileURL(in: dir), encoding: .utf8)
        #expect(onDisk == content)
    }

    @Test("loadFailed clears after the file is fixed and reloaded; save works again")
    func recoversAfterFileFixed() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "name: [unclosed\n  ::: not yaml".write(to: fileURL(in: dir), atomically: true, encoding: .utf8)
        let store = makeStore(in: dir)
        #expect(store.loadFailed)

        try "name: fixed\ncount: 1\n".write(to: fileURL(in: dir), atomically: true, encoding: .utf8)
        store.load()
        #expect(!store.loadFailed)
        #expect(store.data == StubDocument(name: "fixed", count: 1))

        store.update { $0.count = 2 }
        let reloaded = makeStore(in: dir)
        #expect(reloaded.data.count == 2)
    }

    @Test("loadFailed clears when the broken file is removed and reloaded")
    func recoversAfterFileRemoved() throws {
        let dir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "name: [unclosed\n  ::: not yaml".write(to: fileURL(in: dir), atomically: true, encoding: .utf8)
        let store = makeStore(in: dir)
        #expect(store.loadFailed)

        try FileManager.default.removeItem(at: fileURL(in: dir))
        store.load()
        #expect(!store.loadFailed)
    }
}
