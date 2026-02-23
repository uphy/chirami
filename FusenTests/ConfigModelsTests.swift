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
