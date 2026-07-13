import Testing
import Foundation
@testable import Chirami

@Suite("PathTemplateResolver")
struct PathTemplateResolverTests {

    // MARK: - isTemplate

    @Test("identifies path with placeholder as template")
    func isTemplateWithPlaceholder() {
        #expect(PathTemplateResolver.isTemplate("~/notes/{yyyy-MM-dd}.md"))
    }

    @Test("identifies path with multiple placeholders as template")
    func isTemplateWithMultiplePlaceholders() {
        #expect(PathTemplateResolver.isTemplate("~/notes/{yyyy}/{MM}/{dd}.md"))
    }

    @Test("identifies path without placeholder as static")
    func isTemplateWithStaticPath() {
        #expect(!PathTemplateResolver.isTemplate("~/notes/todo.md"))
    }

    @Test("identifies empty string as static path")
    func isTemplateWithEmptyString() {
        #expect(!PathTemplateResolver.isTemplate(""))
    }

    // MARK: - resolve

    @Test("replaces a single placeholder with date string")
    func resolveSinglePlaceholder() {
        let date = makeDate(year: 2026, month: 2, day: 23)
        let result = PathTemplateResolver.resolve("~/notes/daily/{yyyy-MM-dd}.md", for: date)
        #expect(result == "~/notes/daily/2026-02-23.md")
    }

    @Test("resolves multiple placeholders independently")
    func resolveMultiplePlaceholders() {
        let date = makeDate(year: 2026, month: 2, day: 23)
        let result = PathTemplateResolver.resolve("~/notes/{yyyy}/{MM}/{dd}.md", for: date)
        #expect(result == "~/notes/2026/02/23.md")
    }

    @Test("returns static path unchanged")
    func resolveStaticPath() {
        let date = makeDate(year: 2026, month: 2, day: 23)
        let result = PathTemplateResolver.resolve("~/notes/todo.md", for: date)
        #expect(result == "~/notes/todo.md")
    }

    // MARK: - toGlobPattern

    @Test("converts a single placeholder to wildcard")
    func toGlobSinglePlaceholder() {
        let result = PathTemplateResolver.toGlobPattern("~/notes/daily/{yyyy-MM-dd}.md")
        #expect(result == "~/notes/daily/*.md")
    }

    @Test("converts multiple placeholders to wildcards")
    func toGlobMultiplePlaceholders() {
        let result = PathTemplateResolver.toGlobPattern("~/notes/{yyyy}/{MM}/{dd}.md")
        #expect(result == "~/notes/*/*/*.md")
    }

    // MARK: - matches

    @Test("matches a valid date filename")
    func matchesValidDate() {
        #expect(PathTemplateResolver.matches(
            relativePath: "2026-02-23.md",
            template: "~/notes/daily/{yyyy-MM-dd}.md"
        ))
    }

    @Test("matches a relative path with multi-level template")
    func matchesMultiDirectory() {
        #expect(PathTemplateResolver.matches(
            relativePath: "2026/02/23.md",
            template: "~/notes/{yyyy}/{MM}/{dd}.md"
        ))
    }

    @Test("does not match invalid date filename")
    func matchesInvalidDate() {
        #expect(!PathTemplateResolver.matches(
            relativePath: "not-a-date.md",
            template: "~/notes/daily/{yyyy-MM-dd}.md"
        ))
    }

    @Test("does not match file with different extension")
    func matchesDifferentExtension() {
        #expect(!PathTemplateResolver.matches(
            relativePath: "2026-02-23.txt",
            template: "~/notes/daily/{yyyy-MM-dd}.md"
        ))
    }

    @Test("does not match nonexistent date (Feb 30)")
    func matchesNonexistentDate() {
        #expect(!PathTemplateResolver.matches(
            relativePath: "2026-02-30.md",
            template: "~/notes/daily/{yyyy-MM-dd}.md"
        ))
    }

    // MARK: - resolveStream

    @Test("resolveStream resolves placeholders like resolve and strips the wildcard")
    func resolveStreamStripsWildcard() {
        let date = makeDate(year: 2026, month: 7, day: 13)
        let result = PathTemplateResolver.resolveStream("~/notes/claude/{yyyy-MM-dd}-*.md", for: date)
        #expect(result == "~/notes/claude/2026-07-13-.md")
    }

    @Test("resolveStream behaves like resolve when there is no wildcard")
    func resolveStreamWithoutWildcard() {
        let date = makeDate(year: 2026, month: 7, day: 13)
        let result = PathTemplateResolver.resolveStream("~/notes/daily/{yyyy-MM-dd}.md", for: date)
        #expect(result == "~/notes/daily/2026-07-13.md")
    }

    // MARK: - matches (wildcard / stream templates)

    @Test("matches a slugged filename against a wildcard template")
    func matchesWildcardSlug() {
        #expect(PathTemplateResolver.matches(
            relativePath: "2026-07-13-091654-llm-ops.md",
            template: "~/notes/claude/{yyyy-MM-dd-HHmmss}-*.md"
        ))
    }

    @Test("wildcard template matches when the slug is empty")
    func matchesWildcardEmptySlug() {
        #expect(PathTemplateResolver.matches(
            relativePath: "2026-07-13-091654-.md",
            template: "~/notes/claude/{yyyy-MM-dd-HHmmss}-*.md"
        ))
    }

    @Test("wildcard template does not match an unrelated filename")
    func matchesWildcardRejectsUnrelatedFile() {
        #expect(!PathTemplateResolver.matches(
            relativePath: "memo.md",
            template: "~/notes/claude/{yyyy-MM-dd-HHmmss}-*.md"
        ))
    }

    // MARK: - extractBaseDirectory

    @Test("extracts base directory from single-level template")
    func baseDirectorySingleLevel() {
        #expect(PathTemplateResolver.extractBaseDirectory(from: "~/notes/daily/{yyyy-MM-dd}.md") == "~/notes/daily/")
    }

    @Test("extracts base directory from multi-level template")
    func baseDirectoryMultiLevel() {
        #expect(PathTemplateResolver.extractBaseDirectory(from: "~/notes/{yyyy}/{MM}/{dd}.md") == "~/notes/")
    }

    @Test("entire path is the base directory for a static path")
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
