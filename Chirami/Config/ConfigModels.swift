import Foundation
import CryptoKit

// MARK: - Config (~/.config/chirami/config.yaml)

struct AttachmentConfig: Codable {
    var dir: String?
}

enum AppearanceMode: String, Codable {
    case auto
    case light
    case dark
}

struct ChiramiConfig: Codable {
    var appearance: String?
    var font: String?
    var hotkey: String?
    var notes: [NoteConfig] = []
    var adhoc: AdhocConfig?
    var karabiner: KarabinerConfig?
    var smartPaste: SmartPasteConfig?
    var dragModifier: String?
    var warpModifier: String?

    enum CodingKeys: String, CodingKey {
        case appearance, font, hotkey, notes, adhoc, karabiner
        case smartPaste = "smart_paste"
        case dragModifier = "drag_modifier"
        case warpModifier = "warp_modifier"
    }

    var resolvedAppearanceMode: AppearanceMode {
        guard let appearance, let mode = AppearanceMode(rawValue: appearance) else {
            return .auto
        }
        return mode
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

struct NoteConfig: Codable {
    var path: String
    var title: String?
    var color: String?
    var transparency: Double?
    var fontSize: Int?
    var hotkey: String?
    var position: String?
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
        case path, title, color, transparency, hotkey, position, template, attachment
        case fontSize = "font_size"
        case rolloverDelay = "rollover_delay"
    }

    func resolveColor() -> NoteColor {
        if let c = color, let color = NoteColor(rawValue: c) { return color }
        return .yellow
    }

    func resolveTransparency() -> Double {
        transparency ?? 0.9
    }

    func resolveFontSize() -> CGFloat {
        CGFloat(fontSize ?? 14)
    }

    func resolvePosition() -> NotePosition {
        position == "cursor" ? .cursor : .fixed
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

struct AdhocProfile: Codable {
    var title: String?
    var color: String?
    var transparency: Double?
    var fontSize: Int?
    var position: String?       // "cursor" | nil
    var hotkey: String?

    enum CodingKeys: String, CodingKey {
        case title, color, transparency, position, hotkey
        case fontSize = "font_size"
    }

    func resolveColor() -> NoteColor {
        if let c = color, let color = NoteColor(rawValue: c) { return color }
        return .yellow
    }

    func resolveTransparency() -> Double {
        transparency ?? 0.9
    }

    func resolveFontSize() -> CGFloat {
        CGFloat(fontSize ?? 14)
    }

    func resolvePosition() -> NotePosition {
        position == "cursor" ? .cursor : .fixed
    }
}

// MARK: - State (~/.local/state/chirami/state.yaml)

struct ChiramiState: Codable {
    var windows: [String: WindowState] = [:]
    var bookmarks: [String: String] = [:]  // noteId -> Base64 bookmark data
}

struct WindowState: Codable {
    var position: [Double]
    var size: [Double]
    var visible: Bool
    var alwaysOnTop: Bool?
    var pinned: Bool?
    var lastUsed: Date?
    var cursorPosition: Int?
    var scrollOffset: [Double]?

    enum CodingKeys: String, CodingKey {
        case position, size, visible, pinned
        case alwaysOnTop = "always_on_top"
        case lastUsed = "last_used"
        case cursorPosition = "cursor_position"
        case scrollOffset = "scroll_offset"
    }

    init(position: CGPoint, size: CGSize, visible: Bool, alwaysOnTop: Bool? = nil, pinned: Bool? = nil) {
        self.position = [position.x, position.y]
        self.size = [size.width, size.height]
        self.visible = visible
        self.alwaysOnTop = alwaysOnTop
        self.pinned = pinned
    }

    var cgPoint: CGPoint { CGPoint(x: position[0], y: position[1]) }
    var cgSize: CGSize { CGSize(width: size[0], height: size[1]) }
    var scrollCGPoint: CGPoint? {
        guard let offset = scrollOffset, offset.count == 2 else { return nil }
        return CGPoint(x: offset[0], y: offset[1])
    }
}
