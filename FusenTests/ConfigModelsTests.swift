import Testing
import Yams
@testable import Fusen

// MARK: - NoteDefaults Codable

@Suite("NoteDefaults Codable")
struct NoteDefaultsTests {

    @Test("全フィールド指定でデコードできる")
    func decodeAllFields() throws {
        let yaml = """
        color: blue
        transparency: 0.8
        font_size: 16
        """
        let defaults = try YAMLDecoder().decode(NoteDefaults.self, from: yaml)
        #expect(defaults.color == "blue")
        #expect(defaults.transparency == 0.8)
        #expect(defaults.fontSize == 16)
    }

    @Test("部分指定（color のみ）でデコードできる")
    func decodePartialFields() throws {
        let yaml = """
        color: green
        """
        let defaults = try YAMLDecoder().decode(NoteDefaults.self, from: yaml)
        #expect(defaults.color == "green")
        #expect(defaults.transparency == nil)
        #expect(defaults.fontSize == nil)
    }

    @Test("空オブジェクトで全フィールド nil")
    func decodeEmpty() throws {
        let yaml = "{}"
        let defaults = try YAMLDecoder().decode(NoteDefaults.self, from: yaml)
        #expect(defaults.color == nil)
        #expect(defaults.transparency == nil)
        #expect(defaults.fontSize == nil)
    }

    @Test("title や hotkey など未知フィールドは無視される")
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

// MARK: - FusenConfig with defaults

@Suite("FusenConfig defaults フィールド")
struct FusenConfigDefaultsTests {

    @Test("defaults セクション付きの config をデコードできる")
    func decodeWithDefaults() throws {
        let yaml = """
        defaults:
          color: blue
          transparency: 0.7
          font_size: 18
        notes:
          - path: ~/notes/test.md
        """
        let config = try YAMLDecoder().decode(FusenConfig.self, from: yaml)
        #expect(config.defaults != nil)
        #expect(config.defaults?.color == "blue")
        #expect(config.defaults?.transparency == 0.7)
        #expect(config.defaults?.fontSize == 18)
        #expect(config.notes.count == 1)
    }

    @Test("defaults なしの config を従来通りデコードできる（後方互換）")
    func decodeWithoutDefaults() throws {
        let yaml = """
        hotkey: cmd+shift+f
        notes:
          - path: ~/notes/test.md
            color: yellow
        """
        let config = try YAMLDecoder().decode(FusenConfig.self, from: yaml)
        #expect(config.defaults == nil)
        #expect(config.hotkey == "cmd+shift+f")
        #expect(config.notes.count == 1)
    }

    @Test("ルートレベルフィールドが維持される")
    func preservesRootLevelFields() throws {
        let yaml = """
        hotkey: cmd+shift+f
        defaults:
          color: pink
        notes:
          - path: ~/notes/a.md
        karabiner:
          variable: fusen_active
          on_focus: 1
          on_unfocus: 0
        smart_paste:
          enabled: true
          fetch_url_title: false
        """
        let config = try YAMLDecoder().decode(FusenConfig.self, from: yaml)
        #expect(config.hotkey == "cmd+shift+f")
        #expect(config.defaults != nil)
        #expect(config.notes.count == 1)
        #expect(config.karabiner != nil)
        #expect(config.smartPaste != nil)
    }

    @Test("defaults の部分指定を許容する")
    func decodePartialDefaults() throws {
        let yaml = """
        defaults:
          color: purple
        notes: []
        """
        let config = try YAMLDecoder().decode(FusenConfig.self, from: yaml)
        #expect(config.defaults?.color == "purple")
        #expect(config.defaults?.transparency == nil)
        #expect(config.defaults?.fontSize == nil)
    }
}

// MARK: - FusenConfig dragModifier

@Suite("FusenConfig drag_modifier フィールド")
struct FusenConfigDragModifierTests {

    @Test("drag_modifier を指定してデコードできる")
    func decodeDragModifier() throws {
        let yaml = """
        drag_modifier: option
        notes: []
        """
        let config = try YAMLDecoder().decode(FusenConfig.self, from: yaml)
        #expect(config.dragModifier == "option")
    }

    @Test("drag_modifier 未指定で nil になる")
    func decodeDragModifierNil() throws {
        let yaml = """
        notes: []
        """
        let config = try YAMLDecoder().decode(FusenConfig.self, from: yaml)
        #expect(config.dragModifier == nil)
    }

    @Test("サポートする全修飾キーをデコードできる",
          arguments: ["option", "command", "shift", "control"])
    func decodeSupportedModifiers(modifier: String) throws {
        let yaml = """
        drag_modifier: \(modifier)
        notes: []
        """
        let config = try YAMLDecoder().decode(FusenConfig.self, from: yaml)
        #expect(config.dragModifier == modifier)
    }
}

// MARK: - NoteConfig periodic note

@Suite("NoteConfig periodic note 対応")
struct NoteConfigPeriodicNoteTests {

    @Test("periodic note の rollover_delay と template をデコードできる")
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

    @Test("静的ノートは isPeriodicNote が false")
    func staticNoteIsNotPeriodic() throws {
        let yaml = """
        path: ~/notes/todo.md
        """
        let config = try YAMLDecoder().decode(NoteConfig.self, from: yaml)
        #expect(config.isPeriodicNote == false)
        #expect(config.rolloverDelay == nil)
        #expect(config.template == nil)
    }

    @Test("periodic note の noteId はテンプレート文字列から導出される")
    func periodicNoteIdFromTemplate() throws {
        let config1 = NoteConfig(path: "~/notes/daily/{yyyy-MM-dd}.md")
        let config2 = NoteConfig(path: "~/notes/daily/{yyyy-MM-dd}.md")
        #expect(config1.noteId == config2.noteId)
        #expect(config1.isPeriodicNote == true)
    }

    @Test("静的ノートの noteId は resolvedPath から導出される（既存動作維持）")
    func staticNoteIdFromResolvedPath() throws {
        let config = NoteConfig(path: "~/notes/todo.md")
        #expect(config.isPeriodicNote == false)
        // noteId が空でないことを確認
        #expect(!config.noteId.isEmpty)
        #expect(config.noteId.count == 12) // SHA256 先頭6バイト = 12文字の hex
    }

    @Test("periodic note と静的ノートで異なる noteId が導出される")
    func differentNoteIdForPeriodicAndStatic() {
        let periodic = NoteConfig(path: "~/notes/daily/{yyyy-MM-dd}.md")
        let static_ = NoteConfig(path: "~/notes/daily/2026-02-23.md")
        #expect(periodic.noteId != static_.noteId)
    }

    @Test("rollover_delay 未指定でも periodic note として動作する")
    func periodicWithoutRolloverDelay() throws {
        let yaml = """
        path: "~/notes/{yyyy-MM-dd}.md"
        """
        let config = try YAMLDecoder().decode(NoteConfig.self, from: yaml)
        #expect(config.isPeriodicNote == true)
        #expect(config.rolloverDelay == nil)
    }
}
