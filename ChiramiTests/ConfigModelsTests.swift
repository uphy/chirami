import Testing
import Yams
@testable import Chirami

// MARK: - ChiramiConfig dragModifier

@Suite("ChiramiConfig drag_modifier field")
struct ChiramiConfigDragModifierTests {

    @Test("decodes drag_modifier when specified")
    func decodeDragModifier() throws {
        let yaml = """
        drag_modifier: option
        notes: []
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.dragModifier == "option")
    }

    @Test("drag_modifier is nil when not specified")
    func decodeDragModifierNil() throws {
        let yaml = """
        notes: []
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.dragModifier == nil)
    }

    @Test("decodes all supported modifier keys",
          arguments: ["option", "command", "shift", "control"])
    func decodeSupportedModifiers(modifier: String) throws {
        let yaml = """
        drag_modifier: \(modifier)
        notes: []
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.dragModifier == modifier)
    }
}

// MARK: - NoteConfig periodic note

@Suite("NoteConfig periodic note support")
struct NoteConfigPeriodicNoteTests {

    @Test("decodes rollover_delay and template for periodic note")
    func decodePeriodicNoteFields() throws {
        let yaml = """
        path: "~/notes/daily/{yyyy-MM-dd}.md"
        title: "Daily Note"
        rollover_delay: "2h"
        template: ~/notes/templates/daily.md
        """
        let config = try YAMLDecoder().decode(NoteConfig.self, from: yaml)
        #expect(config.rolloverDelay == "2h")
        #expect(config.template == "~/notes/templates/daily.md")
        #expect(config.isPeriodicNote == true)
    }

    @Test("static note has isPeriodicNote false")
    func staticNoteIsNotPeriodic() throws {
        let yaml = """
        path: ~/notes/todo.md
        """
        let config = try YAMLDecoder().decode(NoteConfig.self, from: yaml)
        #expect(config.isPeriodicNote == false)
        #expect(config.rolloverDelay == nil)
        #expect(config.template == nil)
    }

    @Test("periodic note noteId is derived from the template string")
    func periodicNoteIdFromTemplate() throws {
        let config1 = NoteConfig(path: "~/notes/daily/{yyyy-MM-dd}.md")
        let config2 = NoteConfig(path: "~/notes/daily/{yyyy-MM-dd}.md")
        #expect(config1.noteId == config2.noteId)
        #expect(config1.isPeriodicNote == true)
    }

    @Test("static note noteId is derived from resolvedPath (preserves existing behavior)")
    func staticNoteIdFromResolvedPath() throws {
        let config = NoteConfig(path: "~/notes/todo.md")
        #expect(config.isPeriodicNote == false)
        // Verify noteId is non-empty
        #expect(!config.noteId.isEmpty)
        #expect(config.noteId.count == 12) // SHA256 first 6 bytes = 12 hex characters
    }

    @Test("periodic note and static note have different noteIds")
    func differentNoteIdForPeriodicAndStatic() {
        let periodic = NoteConfig(path: "~/notes/daily/{yyyy-MM-dd}.md")
        let static_ = NoteConfig(path: "~/notes/daily/2026-02-23.md")
        #expect(periodic.noteId != static_.noteId)
    }

    @Test("works as periodic note even without rollover_delay")
    func periodicWithoutRolloverDelay() throws {
        let yaml = """
        path: "~/notes/{yyyy-MM-dd}.md"
        """
        let config = try YAMLDecoder().decode(NoteConfig.self, from: yaml)
        #expect(config.isPeriodicNote == true)
        #expect(config.rolloverDelay == nil)
    }
}

// MARK: - NoteConfig resolve methods

@Suite("NoteConfig resolve method")
struct NoteConfigResolveTests {

    @Test("position: returns .cursor when set")
    func resolvePositionCursor() {
        let config = NoteConfig(path: "~/a.md", position: "cursor")
        #expect(config.resolvePosition() == .cursor)
    }

    @Test("position: defaults to .fixed when unset")
    func resolvePositionDefaultsToFixed() {
        let config = NoteConfig(path: "~/a.md")
        #expect(config.resolvePosition() == .fixed)
    }

    @Test("autoHide: returns true when set")
    func resolveAutoHideTrue() {
        let config = NoteConfig(path: "~/a.md", autoHide: true)
        #expect(config.resolveAutoHide() == true)
    }

    @Test("autoHide: defaults to false when unset")
    func resolveAutoHideDefaultsToFalse() {
        let config = NoteConfig(path: "~/a.md")
        #expect(config.resolveAutoHide() == false)
    }

    @Test("color: returns note-level value")
    func resolveColorFromNote() {
        let config = NoteConfig(path: "~/a.md", color: "blue")
        #expect(config.resolveColor() == .blue)
    }

    @Test("color: defaults to yellow when unset")
    func resolveColorDefaultsToYellow() {
        let config = NoteConfig(path: "~/a.md")
        #expect(config.resolveColor() == .yellow)
    }

    @Test("color: falls back to yellow for invalid value")
    func resolveColorInvalidFallsBack() {
        let config = NoteConfig(path: "~/a.md", color: "invalid_color")
        #expect(config.resolveColor() == .yellow)
    }

    @Test("transparency: returns note-level value")
    func resolveTransparencyFromNote() {
        let config = NoteConfig(path: "~/a.md", transparency: 0.5)
        #expect(config.resolveTransparency() == 0.5)
    }

    @Test("transparency: defaults to 0.9 when unset")
    func resolveTransparencyDefault() {
        let config = NoteConfig(path: "~/a.md")
        #expect(config.resolveTransparency() == 0.9)
    }

    @Test("fontSize: returns note-level value")
    func resolveFontSizeFromNote() {
        let config = NoteConfig(path: "~/a.md", fontSize: 20)
        #expect(config.resolveFontSize() == 20)
    }

    @Test("fontSize: defaults to 14 when unset")
    func resolveFontSizeDefault() {
        let config = NoteConfig(path: "~/a.md")
        #expect(config.resolveFontSize() == 14)
    }
}
