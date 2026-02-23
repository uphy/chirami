import Testing
import Foundation
@testable import Chirami

@Suite("PeriodicFileNavigator")
struct PeriodicFileNavigatorTests {

    // MARK: - listMatchingFiles

    @Test("単一階層テンプレートにマッチするファイルをソート済みで返す")
    func listSingleLevel() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create test files
        try createFile(at: dir.appendingPathComponent("2026-02-21.md"))
        try createFile(at: dir.appendingPathComponent("2026-02-23.md"))
        try createFile(at: dir.appendingPathComponent("2026-02-22.md"))
        try createFile(at: dir.appendingPathComponent("notes.txt")) // false positive

        let template = dir.path + "/{yyyy-MM-dd}.md"
        let files = PeriodicFileNavigator.listMatchingFiles(template: template, baseDirectory: dir)

        #expect(files.count == 3)
        #expect(files[0].lastPathComponent == "2026-02-21.md")
        #expect(files[1].lastPathComponent == "2026-02-22.md")
        #expect(files[2].lastPathComponent == "2026-02-23.md")
    }

    @Test("複数階層テンプレートにマッチするファイルを再帰的に列挙する")
    func listMultiLevel() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // ~/notes/{yyyy}/{MM}/{dd}.md 相当の構造を作成
        let dir2026_02 = dir.appendingPathComponent("2026/02")
        let dir2026_01 = dir.appendingPathComponent("2026/01")
        try FileManager.default.createDirectory(at: dir2026_02, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2026_01, withIntermediateDirectories: true)

        try createFile(at: dir2026_01.appendingPathComponent("15.md"))
        try createFile(at: dir2026_02.appendingPathComponent("23.md"))
        try createFile(at: dir2026_02.appendingPathComponent("21.md"))

        let template = dir.path + "/{yyyy}/{MM}/{dd}.md"
        let files = PeriodicFileNavigator.listMatchingFiles(template: template, baseDirectory: dir)

        #expect(files.count == 3)
        // lexicographic sort of relative paths: 2026/01/15.md < 2026/02/21.md < 2026/02/23.md
        #expect(files[0].lastPathComponent == "15.md")
        #expect(files[1].lastPathComponent == "21.md")
        #expect(files[2].lastPathComponent == "23.md")
    }

    @Test("false positive ファイルをフィルタする")
    func filterFalsePositives() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createFile(at: dir.appendingPathComponent("2026-02-23.md"))
        try createFile(at: dir.appendingPathComponent("readme.md"))
        try createFile(at: dir.appendingPathComponent("not-a-date.md"))

        let template = dir.path + "/{yyyy-MM-dd}.md"
        let files = PeriodicFileNavigator.listMatchingFiles(template: template, baseDirectory: dir)

        #expect(files.count == 1)
        #expect(files[0].lastPathComponent == "2026-02-23.md")
    }

    @Test("空のディレクトリでは空配列を返す")
    func listEmpty() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let template = dir.path + "/{yyyy-MM-dd}.md"
        let files = PeriodicFileNavigator.listMatchingFiles(template: template, baseDirectory: dir)

        #expect(files.isEmpty)
    }

    // MARK: - previousFile / nextFile

    @Test("ソート済みリスト内で前のファイルを返す")
    func previousFile() {
        let files = [
            URL(fileURLWithPath: "/a/2026-02-21.md"),
            URL(fileURLWithPath: "/a/2026-02-22.md"),
            URL(fileURLWithPath: "/a/2026-02-23.md"),
        ]
        let result = PeriodicFileNavigator.previousFile(
            from: URL(fileURLWithPath: "/a/2026-02-22.md"), in: files
        )
        #expect(result?.lastPathComponent == "2026-02-21.md")
    }

    @Test("先頭ファイルの前は nil を返す")
    func previousFileAtStart() {
        let files = [
            URL(fileURLWithPath: "/a/2026-02-21.md"),
            URL(fileURLWithPath: "/a/2026-02-22.md"),
        ]
        let result = PeriodicFileNavigator.previousFile(
            from: URL(fileURLWithPath: "/a/2026-02-21.md"), in: files
        )
        #expect(result == nil)
    }

    @Test("ソート済みリスト内で次のファイルを返す")
    func nextFile() {
        let files = [
            URL(fileURLWithPath: "/a/2026-02-21.md"),
            URL(fileURLWithPath: "/a/2026-02-22.md"),
            URL(fileURLWithPath: "/a/2026-02-23.md"),
        ]
        let result = PeriodicFileNavigator.nextFile(
            from: URL(fileURLWithPath: "/a/2026-02-22.md"), in: files
        )
        #expect(result?.lastPathComponent == "2026-02-23.md")
    }

    @Test("末尾ファイルの次は nil を返す")
    func nextFileAtEnd() {
        let files = [
            URL(fileURLWithPath: "/a/2026-02-22.md"),
            URL(fileURLWithPath: "/a/2026-02-23.md"),
        ]
        let result = PeriodicFileNavigator.nextFile(
            from: URL(fileURLWithPath: "/a/2026-02-23.md"), in: files
        )
        #expect(result == nil)
    }

    // MARK: - Helpers

    private func createTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PeriodicFileNavigatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createFile(at url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "".write(to: url, atomically: true, encoding: .utf8)
    }
}
