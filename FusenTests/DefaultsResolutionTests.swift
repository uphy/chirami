import Testing
@testable import Fusen

@Suite("デフォルト値解決 (3段階)")
struct DefaultsResolutionTests {

    // MARK: - color 解決

    @Test("color: ノート個別指定が最優先")
    func colorNoteOverridesDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md", color: "blue")
        let defaults = NoteDefaults(color: "pink")
        #expect(noteConfig.resolveColor(defaults: defaults) == .blue)
    }

    @Test("color: 個別指定なしで defaults を適用")
    func colorFallsBackToDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md")
        let defaults = NoteDefaults(color: "green")
        #expect(noteConfig.resolveColor(defaults: defaults) == .green)
    }

    @Test("color: 両方なしでアプリデフォルト yellow")
    func colorFallsBackToAppDefault() {
        let noteConfig = NoteConfig(path: "~/test.md")
        #expect(noteConfig.resolveColor(defaults: nil) == .yellow)
    }

    @Test("color: defaults のみ指定、個別なし")
    func colorDefaultsOnly() {
        let noteConfig = NoteConfig(path: "~/test.md")
        let defaults = NoteDefaults(color: "purple")
        #expect(noteConfig.resolveColor(defaults: defaults) == .purple)
    }

    @Test("color: 不正な値は無視してアプリデフォルトにフォールバック")
    func colorInvalidValueFallsBack() {
        let noteConfig = NoteConfig(path: "~/test.md", color: "invalid_color")
        let defaults = NoteDefaults(color: "also_invalid")
        #expect(noteConfig.resolveColor(defaults: defaults) == .yellow)
    }

    // MARK: - transparency 解決

    @Test("transparency: ノート個別指定が最優先")
    func transparencyNoteOverridesDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md", transparency: 0.5)
        let defaults = NoteDefaults(transparency: 0.7)
        #expect(noteConfig.resolveTransparency(defaults: defaults) == 0.5)
    }

    @Test("transparency: 個別指定なしで defaults を適用")
    func transparencyFallsBackToDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md")
        let defaults = NoteDefaults(transparency: 0.7)
        #expect(noteConfig.resolveTransparency(defaults: defaults) == 0.7)
    }

    @Test("transparency: 両方なしでアプリデフォルト 0.9")
    func transparencyFallsBackToAppDefault() {
        let noteConfig = NoteConfig(path: "~/test.md")
        #expect(noteConfig.resolveTransparency(defaults: nil) == 0.9)
    }

    // MARK: - fontSize 解決

    @Test("fontSize: ノート個別指定が最優先")
    func fontSizeNoteOverridesDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md", fontSize: 20)
        let defaults = NoteDefaults(fontSize: 16)
        #expect(noteConfig.resolveFontSize(defaults: defaults) == 20)
    }

    @Test("fontSize: 個別指定なしで defaults を適用")
    func fontSizeFallsBackToDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md")
        let defaults = NoteDefaults(fontSize: 16)
        #expect(noteConfig.resolveFontSize(defaults: defaults) == 16)
    }

    @Test("fontSize: 両方なしでアプリデフォルト 14")
    func fontSizeFallsBackToAppDefault() {
        let noteConfig = NoteConfig(path: "~/test.md")
        #expect(noteConfig.resolveFontSize(defaults: nil) == 14)
    }

    // MARK: - 部分指定の組み合わせ

    @Test("部分指定: defaults に color のみ、他はアプリデフォルト")
    func partialDefaultsColorOnly() {
        let noteConfig = NoteConfig(path: "~/test.md")
        let defaults = NoteDefaults(color: "pink")
        #expect(noteConfig.resolveColor(defaults: defaults) == .pink)
        #expect(noteConfig.resolveTransparency(defaults: defaults) == 0.9)
        #expect(noteConfig.resolveFontSize(defaults: defaults) == 14)
    }

    @Test("defaults nil の場合は従来と同じ挙動")
    func nilDefaultsBehavesAsLegacy() {
        let noteConfig = NoteConfig(path: "~/test.md", color: "blue", transparency: 0.8, fontSize: 18)
        #expect(noteConfig.resolveColor(defaults: nil) == .blue)
        #expect(noteConfig.resolveTransparency(defaults: nil) == 0.8)
        #expect(noteConfig.resolveFontSize(defaults: nil) == 18)
    }
}
