import Testing
import Yams
@testable import Chirami

// MARK: - NoteDefaults Codable

@Suite("NoteDefaults Codable")
struct NoteDefaultsTests {

    @Test("decodes all fields")
    func decodeAllFields() throws {
        let yaml = """
        color: blue
        transparency: 0.8
        font_size: 16
        position: cursor
        auto_hide: true
        """
        let defaults = try YAMLDecoder().decode(NoteDefaults.self, from: yaml)
        #expect(defaults.color == "blue")
        #expect(defaults.transparency == 0.8)
        #expect(defaults.fontSize == 16)
        #expect(defaults.position == "cursor")
        #expect(defaults.autoHide == true)
    }

    @Test("decodes partial fields (color only)")
    func decodePartialFields() throws {
        let yaml = """
        color: green
        """
        let defaults = try YAMLDecoder().decode(NoteDefaults.self, from: yaml)
        #expect(defaults.color == "green")
        #expect(defaults.transparency == nil)
        #expect(defaults.fontSize == nil)
        #expect(defaults.position == nil)
        #expect(defaults.autoHide == nil)
    }

    @Test("empty object results in all fields nil")
    func decodeEmpty() throws {
        let yaml = "{}"
        let defaults = try YAMLDecoder().decode(NoteDefaults.self, from: yaml)
        #expect(defaults.color == nil)
        #expect(defaults.transparency == nil)
        #expect(defaults.fontSize == nil)
        #expect(defaults.position == nil)
        #expect(defaults.autoHide == nil)
    }

    @Test("unknown fields like title and hotkey are ignored")
    func ignoresUnknownFields() throws {
        let yaml = """
        color: blue
        title: "should be ignored"
        hotkey: "cmd+1"
        """
        let defaults = try YAMLDecoder().decode(NoteDefaults.self, from: yaml)
        #expect(defaults.color == "blue")
    }
}

// MARK: - ChiramiConfig with defaults

@Suite("ChiramiConfig defaults field")
struct ChiramiConfigDefaultsTests {

    @Test("decodes config with defaults section")
    func decodeWithDefaults() throws {
        let yaml = """
        defaults:
          color: blue
          transparency: 0.7
          font_size: 18
          position: cursor
          auto_hide: true
        notes:
          - path: ~/notes/test.md
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.defaults != nil)
        #expect(config.defaults?.color == "blue")
        #expect(config.defaults?.transparency == 0.7)
        #expect(config.defaults?.fontSize == 18)
        #expect(config.defaults?.position == "cursor")
        #expect(config.defaults?.autoHide == true)
        #expect(config.notes.count == 1)
    }

    @Test("decodes config without defaults (backward compatible)")
    func decodeWithoutDefaults() throws {
        let yaml = """
        hotkey: cmd+shift+f
        notes:
          - path: ~/notes/test.md
            color: yellow
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.defaults == nil)
        #expect(config.hotkey == "cmd+shift+f")
        #expect(config.notes.count == 1)
    }

    @Test("preserves root-level fields")
    func preservesRootLevelFields() throws {
        let yaml = """
        hotkey: cmd+shift+f
        defaults:
          color: pink
        notes:
          - path: ~/notes/a.md
        karabiner:
          variable: chirami_active
          on_focus: 1
          on_unfocus: 0
        smart_paste:
          enabled: true
          fetch_url_title: false
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.hotkey == "cmd+shift+f")
        #expect(config.defaults != nil)
        #expect(config.notes.count == 1)
        #expect(config.karabiner != nil)
        #expect(config.smartPaste != nil)
    }

    @Test("accepts partial defaults")
    func decodePartialDefaults() throws {
        let yaml = """
        defaults:
          color: purple
        notes: []
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.defaults?.color == "purple")
        #expect(config.defaults?.transparency == nil)
        #expect(config.defaults?.fontSize == nil)
    }
}

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

// MARK: - NoteConfig resolve with defaults

@Suite("NoteConfig resolve method")
struct NoteConfigResolveTests {

    @Test("position: note-level overrides defaults")
    func resolvePositionNoteOverridesDefaults() {
        let config = NoteConfig(path: "~/a.md", position: "cursor")
        let defaults = NoteDefaults(position: nil)
        #expect(config.resolvePosition(defaults: defaults) == .cursor)
    }

    @Test("position: falls back to defaults when not set on note")
    func resolvePositionFallsBackToDefaults() {
        let config = NoteConfig(path: "~/a.md")
        let defaults = NoteDefaults(position: "cursor")
        #expect(config.resolvePosition(defaults: defaults) == .cursor)
    }

    @Test("position: defaults to .fixed when both unset")
    func resolvePositionDefaultsToFixed() {
        let config = NoteConfig(path: "~/a.md")
        #expect(config.resolvePosition(defaults: nil) == .fixed)
    }

    @Test("autoHide: note-level overrides defaults")
    func resolveAutoHideNoteOverridesDefaults() {
        let config = NoteConfig(path: "~/a.md", autoHide: true)
        let defaults = NoteDefaults(autoHide: false)
        #expect(config.resolveAutoHide(defaults: defaults) == true)
    }

    @Test("autoHide: falls back to defaults when not set on note")
    func resolveAutoHideFallsBackToDefaults() {
        let config = NoteConfig(path: "~/a.md")
        let defaults = NoteDefaults(autoHide: true)
        #expect(config.resolveAutoHide(defaults: defaults) == true)
    }

    @Test("autoHide: defaults to false when both unset")
    func resolveAutoHideDefaultsToFalse() {
        let config = NoteConfig(path: "~/a.md")
        #expect(config.resolveAutoHide(defaults: nil) == false)
    }
}
