import Testing
import Foundation
@testable import Chirami

@Suite("PathTemplateResolver")
struct PathTemplateResolverTests {

    // MARK: - isTemplate

    @Test("プレースホルダーを含むパスをテンプレートと判定する")
    func isTemplateWithPlaceholder() {
        #expect(PathTemplateResolver.isTemplate("~/notes/{yyyy-MM-dd}.md"))
    }

    @Test("複数プレースホルダーを含むパスをテンプレートと判定する")
    func isTemplateWithMultiplePlaceholders() {
        #expect(PathTemplateResolver.isTemplate("~/notes/{yyyy}/{MM}/{dd}.md"))
    }

    @Test("プレースホルダーを含まないパスは静的パスと判定する")
    func isTemplateWithStaticPath() {
        #expect(!PathTemplateResolver.isTemplate("~/notes/todo.md"))
    }

    @Test("空文字列は静的パスと判定する")
    func isTemplateWithEmptyString() {
        #expect(!PathTemplateResolver.isTemplate(""))
    }

    // MARK: - resolve

    @Test("単一プレースホルダーを日付文字列で置換する")
    func resolveSinglePlaceholder() {
        let date = makeDate(year: 2026, month: 2, day: 23)
        let result = PathTemplateResolver.resolve("~/notes/daily/{yyyy-MM-dd}.md", for: date)
        #expect(result == "~/notes/daily/2026-02-23.md")
    }

    @Test("複数プレースホルダーをそれぞれ解決する")
    func resolveMultiplePlaceholders() {
        let date = makeDate(year: 2026, month: 2, day: 23)
        let result = PathTemplateResolver.resolve("~/notes/{yyyy}/{MM}/{dd}.md", for: date)
        #expect(result == "~/notes/2026/02/23.md")
    }

    @Test("プレースホルダーを含まないパスはそのまま返す")
    func resolveStaticPath() {
        let date = makeDate(year: 2026, month: 2, day: 23)
        let result = PathTemplateResolver.resolve("~/notes/todo.md", for: date)
        #expect(result == "~/notes/todo.md")
    }

    // MARK: - toGlobPattern

    @Test("プレースホルダーをワイルドカードに変換する")
    func toGlobSinglePlaceholder() {
        let result = PathTemplateResolver.toGlobPattern("~/notes/daily/{yyyy-MM-dd}.md")
        #expect(result == "~/notes/daily/*.md")
    }

    @Test("複数プレースホルダーを各々ワイルドカードに変換する")
    func toGlobMultiplePlaceholders() {
        let result = PathTemplateResolver.toGlobPattern("~/notes/{yyyy}/{MM}/{dd}.md")
        #expect(result == "~/notes/*/*/*.md")
    }

    // MARK: - matches

    @Test("有効な日付のファイル名がマッチする")
    func matchesValidDate() {
        #expect(PathTemplateResolver.matches(
            relativePath: "2026-02-23.md",
            template: "~/notes/daily/{yyyy-MM-dd}.md"
        ))
    }

    @Test("複数階層テンプレートの相対パスがマッチする")
    func matchesMultiDirectory() {
        #expect(PathTemplateResolver.matches(
            relativePath: "2026/02/23.md",
            template: "~/notes/{yyyy}/{MM}/{dd}.md"
        ))
    }

    @Test("無効な日付のファイル名はマッチしない")
    func matchesInvalidDate() {
        #expect(!PathTemplateResolver.matches(
            relativePath: "not-a-date.md",
            template: "~/notes/daily/{yyyy-MM-dd}.md"
        ))
    }

    @Test("拡張子が異なるファイルはマッチしない")
    func matchesDifferentExtension() {
        #expect(!PathTemplateResolver.matches(
            relativePath: "2026-02-23.txt",
            template: "~/notes/daily/{yyyy-MM-dd}.md"
        ))
    }

    @Test("存在しない日付（2月30日）はマッチしない")
    func matchesNonexistentDate() {
        #expect(!PathTemplateResolver.matches(
            relativePath: "2026-02-30.md",
            template: "~/notes/daily/{yyyy-MM-dd}.md"
        ))
    }

    // MARK: - extractBaseDirectory

    @Test("単一階層テンプレートのベースディレクトリを取得する")
    func baseDirectorySingleLevel() {
        #expect(PathTemplateResolver.extractBaseDirectory(from: "~/notes/daily/{yyyy-MM-dd}.md") == "~/notes/daily/")
    }

    @Test("複数階層テンプレートのベースディレクトリを取得する")
    func baseDirectoryMultiLevel() {
        #expect(PathTemplateResolver.extractBaseDirectory(from: "~/notes/{yyyy}/{MM}/{dd}.md") == "~/notes/")
    }

    @Test("静的パスはパス全体がベースディレクトリとなる")
    func baseDirectoryStaticPath() {
        #expect(PathTemplateResolver.extractBaseDirectory(from: "~/notes/todo.md") == "~/notes/todo.md")
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }
}
