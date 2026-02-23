import Testing
@testable import Chirami

@Suite("Defaults resolution (3 levels)")
struct DefaultsResolutionTests {

    // MARK: - color resolution

    @Test("color: note-level takes highest priority")
    func colorNoteOverridesDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md", color: "blue")
        let defaults = NoteDefaults(color: "pink")
        #expect(noteConfig.resolveColor(defaults: defaults) == .blue)
    }

    @Test("color: falls back to defaults when not set on note")
    func colorFallsBackToDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md")
        let defaults = NoteDefaults(color: "green")
        #expect(noteConfig.resolveColor(defaults: defaults) == .green)
    }

    @Test("color: falls back to app default yellow when both unset")
    func colorFallsBackToAppDefault() {
        let noteConfig = NoteConfig(path: "~/test.md")
        #expect(noteConfig.resolveColor(defaults: nil) == .yellow)
    }

    @Test("color: uses defaults only when no note-level value")
    func colorDefaultsOnly() {
        let noteConfig = NoteConfig(path: "~/test.md")
        let defaults = NoteDefaults(color: "purple")
        #expect(noteConfig.resolveColor(defaults: defaults) == .purple)
    }

    @Test("color: ignores invalid values and falls back to app default")
    func colorInvalidValueFallsBack() {
        let noteConfig = NoteConfig(path: "~/test.md", color: "invalid_color")
        let defaults = NoteDefaults(color: "also_invalid")
        #expect(noteConfig.resolveColor(defaults: defaults) == .yellow)
    }

    // MARK: - transparency resolution

    @Test("transparency: note-level takes highest priority")
    func transparencyNoteOverridesDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md", transparency: 0.5)
        let defaults = NoteDefaults(transparency: 0.7)
        #expect(noteConfig.resolveTransparency(defaults: defaults) == 0.5)
    }

    @Test("transparency: falls back to defaults when not set on note")
    func transparencyFallsBackToDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md")
        let defaults = NoteDefaults(transparency: 0.7)
        #expect(noteConfig.resolveTransparency(defaults: defaults) == 0.7)
    }

    @Test("transparency: falls back to app default 0.9 when both unset")
    func transparencyFallsBackToAppDefault() {
        let noteConfig = NoteConfig(path: "~/test.md")
        #expect(noteConfig.resolveTransparency(defaults: nil) == 0.9)
    }

    // MARK: - fontSize resolution

    @Test("fontSize: note-level takes highest priority")
    func fontSizeNoteOverridesDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md", fontSize: 20)
        let defaults = NoteDefaults(fontSize: 16)
        #expect(noteConfig.resolveFontSize(defaults: defaults) == 20)
    }

    @Test("fontSize: falls back to defaults when not set on note")
    func fontSizeFallsBackToDefaults() {
        let noteConfig = NoteConfig(path: "~/test.md")
        let defaults = NoteDefaults(fontSize: 16)
        #expect(noteConfig.resolveFontSize(defaults: defaults) == 16)
    }

    @Test("fontSize: falls back to app default 14 when both unset")
    func fontSizeFallsBackToAppDefault() {
        let noteConfig = NoteConfig(path: "~/test.md")
        #expect(noteConfig.resolveFontSize(defaults: nil) == 14)
    }

    // MARK: - partial defaults combinations

    @Test("partial defaults: color only in defaults, others fall back to app default")
    func partialDefaultsColorOnly() {
        let noteConfig = NoteConfig(path: "~/test.md")
        let defaults = NoteDefaults(color: "pink")
        #expect(noteConfig.resolveColor(defaults: defaults) == .pink)
        #expect(noteConfig.resolveTransparency(defaults: defaults) == 0.9)
        #expect(noteConfig.resolveFontSize(defaults: defaults) == 14)
    }

    @Test("nil defaults behaves like legacy behavior")
    func nilDefaultsBehavesAsLegacy() {
        let noteConfig = NoteConfig(path: "~/test.md", color: "blue", transparency: 0.8, fontSize: 18)
        #expect(noteConfig.resolveColor(defaults: nil) == .blue)
        #expect(noteConfig.resolveTransparency(defaults: nil) == 0.8)
        #expect(noteConfig.resolveFontSize(defaults: nil) == 18)
    }
}
