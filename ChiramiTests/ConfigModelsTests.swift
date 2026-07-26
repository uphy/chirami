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

// MARK: - ChiramiConfig warpMargin

@Suite("ChiramiConfig warp_margin field")
struct ChiramiConfigWarpMarginTests {

    @Test("warp_margin defaults to 8 on all edges when omitted")
    func warpMarginDefaults() throws {
        let yaml = """
        notes: []
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.warpMargin == nil)
        #expect(config.resolvedWarpMargin == ResolvedWarpMargin(config: nil))
    }

    @Test("warp_margin decodes partial values and falls back per edge")
    func decodePartialWarpMargin() throws {
        let yaml = """
        warp_margin:
          top: 24
          right: 48
        notes: []
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.warpMargin == WarpMarginConfig(top: 24, right: 48, bottom: nil, left: nil))
        #expect(config.resolvedWarpMargin == ResolvedWarpMargin(
            config: WarpMarginConfig(top: 24, right: 48, bottom: nil, left: nil)
        ))
    }

    @Test("warp_margin negative values fall back to defaults")
    func negativeWarpMarginFallsBack() throws {
        let yaml = """
        warp_margin:
          top: -1
          right: 12
          bottom: -3
          left: 0
        notes: []
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.resolvedWarpMargin == ResolvedWarpMargin(
            config: WarpMarginConfig(top: nil, right: 12, bottom: nil, left: 0)
        ))
    }
}

// MARK: - HotkeyBinding

@Suite("Hotkey binding config")
struct HotkeyBindingConfigTests {

    @Test("decodes top-level hotkeys")
    func decodeGlobalHotkeys() throws {
        let yaml = """
        hotkeys:
          - key: cmd+shift+n
            action: toggle
        notes: []
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.hotkeys == [HotkeyBinding(key: "cmd+shift+n", action: .toggle)])
    }

    @Test("hotkey binding action defaults to toggle")
    func hotkeyBindingDefaultAction() throws {
        let yaml = """
        path: ~/notes/todo.md
        hotkeys:
          - key: cmd+shift+t
        """
        let config = try YAMLDecoder().decode(NoteConfig.self, from: yaml)
        #expect(config.hotkeys == [HotkeyBinding(key: "cmd+shift+t", action: .toggle)])
    }

    @Test("adhoc profile decodes multiple hotkeys")
    func decodeAdhocProfileHotkeys() throws {
        let yaml = """
        title: Meeting
        hotkeys:
          - key: cmd+shift+m
            action: toggle
          - key: cmd+shift+option+m
            action: toggle
        """
        let profile = try YAMLDecoder().decode(AdhocProfile.self, from: yaml)
        #expect(profile.hotkeys == [
            HotkeyBinding(key: "cmd+shift+m", action: .toggle),
            HotkeyBinding(key: "cmd+shift+option+m", action: .toggle),
        ])
    }

    @Test("legacy hotkey field is ignored")
    func legacyHotkeyIgnored() throws {
        let yaml = """
        path: ~/notes/todo.md
        hotkey: cmd+shift+t
        """
        let config = try YAMLDecoder().decode(NoteConfig.self, from: yaml)
        #expect(config.hotkeys.isEmpty)
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

// MARK: - NoteConfig mode / stream validation

@Suite("NoteConfig mode field and stream validation")
struct NoteConfigModeTests {

    // MARK: - mode decoding / backward compatibility

    @Test("mode defaults to periodic when omitted (backward compatible)")
    func modeDefaultsToPeriodicWhenOmitted() throws {
        let yaml = """
        path: "~/notes/daily/{yyyy-MM-dd}.md"
        title: "Daily Note"
        rollover_delay: "2h"
        template: ~/notes/templates/daily.md
        """
        let config = try YAMLDecoder().decode(NoteConfig.self, from: yaml)
        #expect(config.mode == .periodic)
        // Existing fields still parse exactly as before.
        #expect(config.rolloverDelay == "2h")
        #expect(config.template == "~/notes/templates/daily.md")
        #expect(config.isPeriodicNote == true)
        #expect(config.configErrors.isEmpty)
    }

    @Test("mode decodes explicit periodic and stream values")
    func modeDecodesExplicitValues() throws {
        let periodicYaml = """
        path: "~/notes/daily/{yyyy-MM-dd}.md"
        mode: periodic
        """
        let periodic = try YAMLDecoder().decode(NoteConfig.self, from: periodicYaml)
        #expect(periodic.mode == .periodic)

        let streamYaml = """
        path: "~/notes/claude/{yyyy-MM-dd-HHmmss}.md"
        mode: stream
        """
        let stream = try YAMLDecoder().decode(NoteConfig.self, from: streamYaml)
        #expect(stream.mode == .stream)
    }

    // MARK: - configErrors: mode validation

    @Test("stream mode with a placeholder path is valid")
    func streamModeWithPlaceholderIsValid() {
        let config = NoteConfig(path: "~/notes/claude/{yyyy-MM-dd-HHmmss}.md", mode: .stream)
        #expect(config.configErrors.isEmpty)
        #expect(config.isConfigValid)
    }

    @Test("stream mode without a placeholder is a config error")
    func streamModeWithoutPlaceholderIsInvalid() {
        let config = NoteConfig(path: "~/notes/memo.md", mode: .stream)
        #expect(config.configErrors == [.streamRequiresPlaceholder])
        #expect(!config.isConfigValid)
    }

    @Test("stream mode with a placeholder in the directory component is a config error")
    func streamModePlaceholderInDirectoryIsInvalid() {
        let config = NoteConfig(path: "~/notes/{yyyy}/{MM}/{dd}.md", mode: .stream)
        #expect(config.configErrors.contains(.streamPlaceholderMustBeInFilename))
    }

    @Test("periodic mode is unaffected by stream-only validation")
    func periodicModeHasNoStreamErrors() {
        let config = NoteConfig(path: "~/notes/{yyyy}/{MM}/{dd}.md", mode: .periodic)
        #expect(config.configErrors.isEmpty)
    }

    // MARK: - configErrors: wildcard validation

    @Test("single wildcard in the filename component is valid for stream mode")
    func singleWildcardInFilenameIsValid() {
        let config = NoteConfig(path: "~/notes/claude/{yyyy-MM-dd-HHmmss}-*.md", mode: .stream)
        #expect(config.configErrors.isEmpty)
    }

    @Test("multiple wildcards in the filename component is a config error")
    func multipleWildcardsInFilenameIsInvalid() {
        let config = NoteConfig(path: "~/notes/claude/{yyyy-MM-dd-HHmmss}-*-*.md", mode: .stream)
        #expect(config.configErrors.contains(.multipleWildcardsInFilename))
    }

    @Test("wildcard in the directory component is a config error")
    func wildcardInDirectoryComponentIsInvalid() {
        let config = NoteConfig(path: "~/notes/*/{yyyy-MM-dd-HHmmss}.md", mode: .stream)
        #expect(config.configErrors.contains(.wildcardInDirectoryComponent))
    }

    @Test("wildcard with periodic mode is a config error")
    func wildcardWithPeriodicModeIsInvalid() {
        let config = NoteConfig(path: "~/notes/daily/{yyyy-MM-dd}-*.md", mode: .periodic)
        #expect(config.configErrors.contains(.wildcardRequiresStreamMode))
    }

    // MARK: - rollover_delay + stream combination (warning only, still registers)

    @Test("rollover_delay combined with stream mode still parses (warning is logged, not a config error)")
    func rolloverDelayWithStreamModeStillParses() throws {
        let yaml = """
        path: "~/notes/claude/{yyyy-MM-dd-HHmmss}.md"
        mode: stream
        rollover_delay: "4h"
        """
        let config = try YAMLDecoder().decode(NoteConfig.self, from: yaml)
        #expect(config.mode == .stream)
        #expect(config.rolloverDelay == "4h")
        #expect(config.configErrors.isEmpty)
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

}

// MARK: - WindowState pinned

@Suite("WindowState pinned field")
struct WindowStatePinnedTests {

    @Test("pinned decodes from YAML when specified")
    func decodePinnedFromYAML() throws {
        let yaml = """
        position: [100, 200]
        size: [300, 400]
        visible: true
        pinned: true
        """
        let state = try YAMLDecoder().decode(WindowState.self, from: yaml)
        #expect(state.pinned == true)
    }

    @Test("pinned is nil when not specified")
    func decodePinnedNilWhenUnspecified() throws {
        let yaml = """
        position: [100, 200]
        size: [300, 400]
        visible: true
        """
        let state = try YAMLDecoder().decode(WindowState.self, from: yaml)
        #expect(state.pinned == nil)
    }

    @Test("pinned false decodes correctly")
    func decodePinnedFalse() throws {
        let yaml = """
        position: [100, 200]
        size: [300, 400]
        visible: true
        pinned: false
        """
        let state = try YAMLDecoder().decode(WindowState.self, from: yaml)
        #expect(state.pinned == false)
    }
}
