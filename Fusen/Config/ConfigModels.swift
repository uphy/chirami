import Foundation
import CryptoKit

// MARK: - Config (~/.config/fusen/config.yaml)

struct NoteDefaults: Codable {
    var color: String?
    var transparency: Double?
    var fontSize: Int?

    enum CodingKeys: String, CodingKey {
        case color, transparency
        case fontSize = "font_size"
    }
}

struct FusenConfig: Codable {
    var hotkey: String?
    var defaults: NoteDefaults?
    var notes: [NoteConfig] = []
    var karabiner: KarabinerConfig?
    var smartPaste: SmartPasteConfig?
    var dragModifier: String?

    enum CodingKeys: String, CodingKey {
        case hotkey, defaults, notes, karabiner
        case smartPaste = "smart_paste"
        case dragModifier = "drag_modifier"
    }
}

#if canImport(AppKit)
import AppKit

extension FusenConfig {
    var dragModifierFlags: NSEvent.ModifierFlags {
        switch dragModifier {
        case "option": return .option
        case "shift": return .shift
        case "control": return .control
        default: return .command
        }
    }
}
#endif

struct SmartPasteConfig: Codable {
    var enabled: Bool = true
    var fetchUrlTitle: Bool = true

    enum CodingKeys: String, CodingKey {
        case enabled
        case fetchUrlTitle = "fetch_url_title"
    }
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

struct NoteConfig: Codable {
    var path: String
    var title: String?
    var color: String?
    var transparency: Double?
    var fontSize: Int?
    var hotkey: String?
    var position: String?
    var autoHide: Bool?
    var rolloverDelay: String?
    var template: String?

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
        case path, title, color, transparency, hotkey, position, template
        case fontSize = "font_size"
        case autoHide = "auto_hide"
        case rolloverDelay = "rollover_delay"
    }

    func resolveColor(defaults: NoteDefaults?) -> NoteColor {
        if let c = color, let color = NoteColor(rawValue: c) { return color }
        if let c = defaults?.color, let color = NoteColor(rawValue: c) { return color }
        return .yellow
    }

    func resolveTransparency(defaults: NoteDefaults?) -> Double {
        transparency ?? defaults?.transparency ?? 0.9
    }

    func resolveFontSize(defaults: NoteDefaults?) -> CGFloat {
        CGFloat(fontSize ?? defaults?.fontSize ?? 14)
    }
}

// MARK: - State (~/.local/state/fusen/state.yaml)

struct FusenState: Codable {
    var windows: [String: WindowState] = [:]
    var bookmarks: [String: String] = [:]  // noteId -> Base64 bookmark data
}

struct WindowState: Codable {
    var position: [Double]
    var size: [Double]
    var visible: Bool
    var alwaysOnTop: Bool?

    enum CodingKeys: String, CodingKey {
        case position, size, visible
        case alwaysOnTop = "always_on_top"
    }

    init(position: CGPoint, size: CGSize, visible: Bool, alwaysOnTop: Bool? = nil) {
        self.position = [position.x, position.y]
        self.size = [size.width, size.height]
        self.visible = visible
        self.alwaysOnTop = alwaysOnTop
    }

    var cgPoint: CGPoint { CGPoint(x: position[0], y: position[1]) }
    var cgSize: CGSize { CGSize(width: size[0], height: size[1]) }
}
