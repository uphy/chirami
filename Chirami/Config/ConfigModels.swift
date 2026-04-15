import Foundation
import CryptoKit

// MARK: - Config (~/.config/chirami/config.yaml)

// MARK: - NoteAppearanceResolvable

protocol NoteAppearanceResolvable {
    var transparency: Double? { get }
    var position: String? { get }
    var alwaysOnTop: Bool? { get }
}

extension NoteAppearanceResolvable {
    func resolveTransparency() -> Double {
        transparency ?? 0.9
    }

    func resolvePosition() -> NotePosition {
        position == "cursor" ? .cursor : .fixed
    }

    func resolveAlwaysOnTop() -> Bool {
        alwaysOnTop ?? true
    }
}

struct AttachmentConfig: Codable {
    var dir: String?
}

enum AppearanceMode: String, Codable {
    case auto
    case light
    case dark

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AppearanceMode(rawValue: raw) ?? .auto
    }
}

/// Global appearance configuration: display mode and optional CSS file path.
/// Supports both legacy string format (`appearance: auto`) and object format.
struct AppearanceConfig: Codable, Equatable {
    var mode: AppearanceMode = .auto
    var cssFile: String?
    var variables: [String: String]?

    enum CodingKeys: String, CodingKey {
        case mode
        case cssFile = "css_file"
        case variables
    }

    init(mode: AppearanceMode = .auto, cssFile: String? = nil, variables: [String: String]? = nil) {
        self.mode = mode
        self.cssFile = cssFile
        self.variables = variables
    }

    init(from decoder: Decoder) throws {
        // Try the legacy scalar form first (`appearance: auto`) — it's narrow and decodes
        // unambiguously. Fall back to the keyed object form for the current schema.
        if let single = try? decoder.singleValueContainer(),
           let mode = try? single.decode(AppearanceMode.self) {
            self.mode = mode
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? container.decode(AppearanceMode.self, forKey: .mode)) ?? .auto
        cssFile = try? container.decode(String.self, forKey: .cssFile)
        variables = try? container.decode([String: String].self, forKey: .variables)
    }
}

struct ExcalidrawConfig: Codable {
    var libraries: [String]?
}

struct TranscriptDeviceConfig: Codable, Equatable {
    var mic: String
    var system: String

    enum CodingKeys: String, CodingKey {
        case mic
        case system
    }

    init(mic: String = "default", system: String = "auto") {
        self.mic = mic
        self.system = system
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mic = try container.decodeIfPresent(String.self, forKey: .mic) ?? "default"
        system = try container.decodeIfPresent(String.self, forKey: .system) ?? "auto"
    }
}

struct TranscriptLabelConfig: Codable, Equatable {
    var mic: String
    var system: String

    enum CodingKeys: String, CodingKey {
        case mic
        case system
    }

    init(mic: String = "You", system: String = "Others") {
        self.mic = mic
        self.system = system
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mic = try container.decodeIfPresent(String.self, forKey: .mic) ?? "You"
        system = try container.decodeIfPresent(String.self, forKey: .system) ?? "Others"
    }
}

struct TranscriptConfig: Codable, Equatable {
    var model: String
    var language: String
    var devices: TranscriptDeviceConfig
    var labels: TranscriptLabelConfig

    enum CodingKeys: String, CodingKey {
        case model
        case language
        case devices
        case labels
    }

    init(
        model: String = "openai_whisper-large-v3_turbo",
        language: String = "auto",
        devices: TranscriptDeviceConfig = TranscriptDeviceConfig(),
        labels: TranscriptLabelConfig = TranscriptLabelConfig()
    ) {
        self.model = model
        self.language = language
        self.devices = devices
        self.labels = labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "openai_whisper-large-v3_turbo"
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        devices = try container.decodeIfPresent(TranscriptDeviceConfig.self, forKey: .devices) ?? TranscriptDeviceConfig()
        labels = try container.decodeIfPresent(TranscriptLabelConfig.self, forKey: .labels) ?? TranscriptLabelConfig()
    }
}

struct ChiramiConfig: Codable {
    var appearance: AppearanceConfig?
    var hotkey: String?
    var launchAtLogin: Bool?
    var showMenuBarIcon: Bool?
    var notes: [NoteConfig] = []
    var adhoc: AdhocConfig?
    var karabiner: KarabinerConfig?
    var smartPaste: SmartPasteConfig?
    var dragModifier: String?
    var warpModifier: String?
    var excalidraw: ExcalidrawConfig?
    var transcript: TranscriptConfig?

    enum CodingKeys: String, CodingKey {
        case appearance, hotkey, notes, adhoc, karabiner, excalidraw, transcript
        case launchAtLogin = "launch_at_login"
        case showMenuBarIcon = "show_menu_bar_icon"
        case smartPaste = "smart_paste"
        case dragModifier = "drag_modifier"
        case warpModifier = "warp_modifier"
    }
}

#if canImport(AppKit)
import AppKit

extension ChiramiConfig {
    var dragModifierFlags: NSEvent.ModifierFlags {
        switch dragModifier {
        case "option": return .option
        case "shift": return .shift
        case "control": return .control
        default: return .command
        }
    }

    var warpModifierFlags: NSEvent.ModifierFlags {
        let parts = (warpModifier ?? "ctrl+option").lowercased().components(separatedBy: "+")
        var flags: NSEvent.ModifierFlags = []
        for part in parts {
            switch part {
            case "ctrl", "control": flags.insert(.control)
            case "option", "opt":   flags.insert(.option)
            case "command", "cmd":  flags.insert(.command)
            case "shift":           flags.insert(.shift)
            default: break
            }
        }
        // Fall back to ctrl+option if no valid modifiers were parsed
        return flags.isEmpty ? [.control, .option] : flags
    }
}

extension ChiramiConfig {
    var resolvedTranscript: TranscriptConfig {
        transcript ?? TranscriptConfig()
    }
}
#endif

struct SmartPasteConfig: Codable {
    var enabled: Bool = true
}

struct KarabinerConfig: Codable {
    var variable: String
    var onFocus: KarabinerValue
    var onUnfocus: KarabinerValue
    var cliPath: String?

    enum CodingKeys: String, CodingKey {
        case variable
        case onFocus = "on_focus"
        case onUnfocus = "on_unfocus"
        case cliPath = "cli_path"
    }
}

/// A value that can be either an integer or a string, matching Karabiner-Elements variable types.
enum KarabinerValue: Codable, Equatable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }

    /// JSON fragment for use in karabiner_cli --set-variables argument.
    var jsonFragment: String {
        switch self {
        case .int(let value): return "\(value)"
        case .string(let value): return "\"\(value)\""
        }
    }
}

struct NoteConfig: Codable, NoteAppearanceResolvable {
    var path: String
    var title: String?
    var theme: String?
    var transparency: Double?
    var hotkey: String?
    var position: String?
    var alwaysOnTop: Bool?
    var rolloverDelay: String?
    var template: String?
    var attachment: AttachmentConfig?

    var isPeriodicNote: Bool {
        PathTemplateResolver.isTemplate(path)
    }

    var resolvedPath: String {
        if path.hasPrefix("~/") {
            return FileManager.realHomeDirectory.path + "/" + path.dropFirst(2)
        }
        return path
    }

    var noteId: String {
        let source = isPeriodicNote ? path : resolvedPath
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    enum CodingKeys: String, CodingKey {
        case path, title, theme, transparency, hotkey, position, template, attachment
        case alwaysOnTop = "always_on_top"
        case rolloverDelay = "rollover_delay"
    }

    func resolveAttachmentsDir(noteURL: URL, isPeriodicNote: Bool, pathTemplate: String?) -> URL {
        let dir = attachment?.dir
        guard let dir else {
            if isPeriodicNote, let pathTemplate {
                // Periodic note: template parent directory + "attachments/"
                let baseDir = PathTemplateResolver.extractBaseDirectory(from: pathTemplate)
                let baseDirResolved: URL
                if baseDir.hasPrefix("~/") {
                    baseDirResolved = URL(fileURLWithPath: (baseDir as NSString).expandingTildeInPath)
                } else if baseDir.hasPrefix("/") {
                    baseDirResolved = URL(fileURLWithPath: baseDir)
                } else {
                    baseDirResolved = noteURL.deletingLastPathComponent()
                }
                return baseDirResolved.appendingPathComponent("attachments")
            }
            // Static note: <note-stem>.attachments/
            let stem = noteURL.deletingPathExtension().lastPathComponent
            return noteURL.deletingLastPathComponent()
                .appendingPathComponent("\(stem).attachments")
        }
        if dir.hasPrefix("~/") {
            let expanded = (dir as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        if dir.hasPrefix("/") {
            return URL(fileURLWithPath: dir)
        }
        // Relative path: resolve from note's parent directory
        return noteURL.deletingLastPathComponent()
            .appendingPathComponent(dir)
    }
}

// MARK: - Adhoc Config

struct AdhocConfig: Codable {
    var profiles: [String: AdhocProfile]?
}

struct AdhocProfile: Codable, NoteAppearanceResolvable {
    var title: String?
    var theme: String?
    var transparency: Double?
    var position: String?       // "cursor" | nil
    var alwaysOnTop: Bool?
    var hotkey: String?

    enum CodingKeys: String, CodingKey {
        case title, theme, transparency, position, hotkey
        case alwaysOnTop = "always_on_top"
    }

}

// MARK: - Folding State

struct FoldingState: Codable {
    /// 1-based line numbers of folded foldable block starts (keyed by resolved file path).
    var foldedLines: Set<Int> = []

    enum CodingKeys: String, CodingKey {
        case foldedLines = "folded_lines"
    }
}

// MARK: - State (~/.local/state/chirami/state.yaml)

struct ChiramiState: Codable {
    var windows: [String: WindowState] = [:]
    var bookmarks: [String: String] = [:]  // noteId -> Base64 bookmark data
    var foldingStates: [String: FoldingState] = [:]  // resolved file path -> FoldingState
    var lastMic: String?
    var lastSystemSource: String?

    enum CodingKeys: String, CodingKey {
        case windows, bookmarks
        case foldingStates = "folding_states"
        case lastMic = "last_mic"
        case lastSystemSource = "last_system_source"
    }
}

struct WindowState: Codable {
    var position: [Double]
    var size: [Double]
    var visible: Bool
    var pinned: Bool?
    var lastUsed: Date?
    var cursorPosition: Int?
    var scrollOffset: [Double]?

    enum CodingKeys: String, CodingKey {
        case position, size, visible, pinned
        case lastUsed = "last_used"
        case cursorPosition = "cursor_position"
        case scrollOffset = "scroll_offset"
    }

    init(position: CGPoint, size: CGSize, visible: Bool, pinned: Bool? = nil) {
        self.position = [position.x, position.y]
        self.size = [size.width, size.height]
        self.visible = visible
        self.pinned = pinned
    }

    var cgPoint: CGPoint { CGPoint(x: position[0], y: position[1]) }
    var cgSize: CGSize { CGSize(width: size[0], height: size[1]) }
    var scrollCGPoint: CGPoint? {
        guard let offset = scrollOffset, offset.count == 2 else { return nil }
        return CGPoint(x: offset[0], y: offset[1])
    }
}
