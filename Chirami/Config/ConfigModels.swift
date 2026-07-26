import Foundation
import CryptoKit
import os

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

/// A command template for opening a resolved file. YAML accepts two shapes:
///
/// - Array form (`["code", "{{path}}"]`): executed directly without a shell,
///   so file names with special characters never trigger shell expansion.
/// - String form (`"code $CHIRAMI_TARGET"`): executed via `/bin/sh -c`, so
///   shell features and `$CHIRAMI_*` environment variables are available.
enum CommandTemplate: Codable, Equatable {
    case args([String])
    case shell(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            self = .args(array)
        } else {
            self = .shell(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .args(let array): try container.encode(array)
        case .shell(let string): try container.encode(string)
        }
    }
}

/// Configuration for `[[wiki link]]` resolution and opening.
///
/// `open` is the command run with the resolved file (array form is preferred
/// and used as the default when omitted). `vault` pins the search root; when
/// absent, the resolver walks up from the source note looking for `.obsidian`.
struct WikiLinkConfig: Codable, Equatable {
    var open: CommandTemplate?
    var vault: String?
}

struct ChiramiConfig: Codable {
    var appearance: AppearanceConfig?
    var hotkeys: [HotkeyBinding]?
    var launchAtLogin: Bool?
    var showMenuBarIcon: Bool?
    var notes: [NoteConfig] = []
    var adhoc: AdhocConfig?
    var karabiner: KarabinerConfig?
    var smartPaste: SmartPasteConfig?
    var dragModifier: String?
    var warpModifier: String?
    var warpMargin: WarpMarginConfig?
    var excalidraw: ExcalidrawConfig?
    var wikilink: WikiLinkConfig?

    enum CodingKeys: String, CodingKey {
        case appearance, hotkeys, notes, adhoc, karabiner, excalidraw, wikilink
        case launchAtLogin = "launch_at_login"
        case showMenuBarIcon = "show_menu_bar_icon"
        case smartPaste = "smart_paste"
        case dragModifier = "drag_modifier"
        case warpModifier = "warp_modifier"
        case warpMargin = "warp_margin"
    }
}

struct WarpMarginConfig: Codable, Equatable {
    var top: Double?
    var right: Double?
    var bottom: Double?
    var left: Double?
}

#if canImport(AppKit)
import AppKit

struct ResolvedWarpMargin: Equatable {
    static let defaultValue: CGFloat = 8

    let top: CGFloat
    let right: CGFloat
    let bottom: CGFloat
    let left: CGFloat

    init(config: WarpMarginConfig?) {
        top = Self.resolve(config?.top)
        right = Self.resolve(config?.right)
        bottom = Self.resolve(config?.bottom)
        left = Self.resolve(config?.left)
    }

    private static func resolve(_ value: Double?) -> CGFloat {
        guard let value, value >= 0 else { return defaultValue }
        return CGFloat(value)
    }
}

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

    var resolvedWarpMargin: ResolvedWarpMargin {
        ResolvedWarpMargin(config: warpMargin)
    }
}
#endif

struct SmartPasteConfig: Codable {
    var enabled: Bool = true
}

enum HotkeyAction: String, Codable, Equatable {
    case toggle
    case create
}

struct HotkeyBinding: Codable, Equatable {
    var key: String
    var action: HotkeyAction

    init(key: String, action: HotkeyAction = .toggle) {
        self.key = key
        self.action = action
    }

    enum CodingKeys: String, CodingKey {
        case key, action
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        action = try container.decodeIfPresent(HotkeyAction.self, forKey: .action) ?? .toggle
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

/// The two flavors of a template-path (`{...}`) registered note.
///
/// - `periodic`: "current" resolves from the current time (`PathTemplateResolver.resolve`);
///   the rollover timer keeps it in sync as the period changes.
/// - `stream`: "current" resolves to the lexicographically last matching file
///   (see `PeriodicFileNavigator.latestMatchingFile`); the rollover timer does
///   not apply.
///
/// Absent `mode` in YAML decodes to `.periodic`, so existing configs are
/// unaffected.
enum NoteMode: String, Codable, Equatable {
    case periodic
    case stream
}

/// Configuration errors for a `NoteConfig` that prevent the note from being
/// registered. Mirrors how other unresolvable notes are already dropped in
/// `NoteStore` (silently excluded from `notes[]`); callers should log these
/// via the standard warn-level config logging convention and skip the note.
enum NoteConfigError: Error, Equatable, CustomStringConvertible {
    /// `mode: stream` on a path without any `{...}` placeholder.
    case streamRequiresPlaceholder
    /// `mode: stream` with a `{...}` placeholder outside the filename component.
    case streamPlaceholderMustBeInFilename
    /// `*` present but `mode` is not `stream`.
    case wildcardRequiresStreamMode
    /// `*` present in the directory component instead of the filename component.
    case wildcardInDirectoryComponent
    /// More than one `*` in the filename component.
    case multipleWildcardsInFilename

    var description: String {
        switch self {
        case .streamRequiresPlaceholder:
            return "mode: stream requires the path to contain a {...} placeholder"
        case .streamPlaceholderMustBeInFilename:
            return "mode: stream placeholders are only allowed in the filename component, not the directory component"
        case .wildcardRequiresStreamMode:
            return "* wildcard is only allowed with mode: stream"
        case .wildcardInDirectoryComponent:
            return "* wildcard is only allowed in the filename component, not the directory component"
        case .multipleWildcardsInFilename:
            return "only a single * wildcard is allowed in the filename component"
        }
    }
}

struct NoteConfig: Codable, NoteAppearanceResolvable {
    var path: String
    var title: String?
    var theme: String?
    var transparency: Double?
    var hotkeys: [HotkeyBinding] = []
    var position: String?
    var alwaysOnTop: Bool?
    var rolloverDelay: String?
    var template: String?
    var attachment: AttachmentConfig?
    /// Per-note override for `[[wiki link]]` opening. Falls back field-by-field
    /// to the global `wikilink` config when absent.
    var wikilink: WikiLinkConfig?
    /// `periodic` (default) or `stream`. Only meaningful for template-path notes.
    var mode: NoteMode = .periodic

    var isPeriodicNote: Bool {
        PathTemplateResolver.isTemplate(path)
    }

    /// Validation errors that should prevent this note from being registered.
    /// Empty when the config is valid.
    var configErrors: [NoteConfigError] {
        var errors: [NoteConfigError] = []

        let hasPlaceholder = PathTemplateResolver.isTemplate(path)
        let filenameComponent = (path as NSString).lastPathComponent
        let directoryComponent = (path as NSString).deletingLastPathComponent
        let wildcardCountInFilename = filenameComponent.filter { $0 == "*" }.count
        let hasWildcardInDirectory = directoryComponent.contains("*")

        if mode == .stream {
            if !hasPlaceholder {
                errors.append(.streamRequiresPlaceholder)
            } else if PathTemplateResolver.isTemplate(directoryComponent) {
                errors.append(.streamPlaceholderMustBeInFilename)
            }
        }

        if wildcardCountInFilename > 0 || hasWildcardInDirectory {
            if mode != .stream {
                errors.append(.wildcardRequiresStreamMode)
            }
            if hasWildcardInDirectory {
                errors.append(.wildcardInDirectoryComponent)
            }
            if wildcardCountInFilename > 1 {
                errors.append(.multipleWildcardsInFilename)
            }
        }

        return errors
    }

    var isConfigValid: Bool {
        configErrors.isEmpty
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
        case path, title, theme, transparency, hotkeys, position, template, attachment, wikilink, mode
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

// Custom decoding lives in an extension so the memberwise initializer is preserved.
extension NoteConfig {
    private static let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "NoteConfig")

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        theme = try container.decodeIfPresent(String.self, forKey: .theme)
        transparency = try container.decodeIfPresent(Double.self, forKey: .transparency)
        // `hotkeys` is optional in YAML; default to an empty list when omitted.
        hotkeys = try container.decodeIfPresent([HotkeyBinding].self, forKey: .hotkeys) ?? []
        position = try container.decodeIfPresent(String.self, forKey: .position)
        alwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .alwaysOnTop)
        rolloverDelay = try container.decodeIfPresent(String.self, forKey: .rolloverDelay)
        template = try container.decodeIfPresent(String.self, forKey: .template)
        attachment = try container.decodeIfPresent(AttachmentConfig.self, forKey: .attachment)
        wikilink = try container.decodeIfPresent(WikiLinkConfig.self, forKey: .wikilink)
        // `mode` is optional in YAML; absent means `.periodic` (backward compatible).
        mode = try container.decodeIfPresent(NoteMode.self, forKey: .mode) ?? .periodic

        if mode == .stream, rolloverDelay != nil {
            let notePath = path
            Self.logger.warning("mode: stream is combined with rollover_delay for path \(notePath, privacy: .public); rollover_delay is ignored for stream notes")
        }
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
    var hotkeys: [HotkeyBinding] = []

    enum CodingKeys: String, CodingKey {
        case title, theme, transparency, position, hotkeys
        case alwaysOnTop = "always_on_top"
    }

}

// Custom decoding lives in an extension so the memberwise initializer is preserved.
extension AdhocProfile {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        theme = try container.decodeIfPresent(String.self, forKey: .theme)
        transparency = try container.decodeIfPresent(Double.self, forKey: .transparency)
        position = try container.decodeIfPresent(String.self, forKey: .position)
        alwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .alwaysOnTop)
        // `hotkeys` is optional in YAML; default to an empty list when omitted.
        hotkeys = try container.decodeIfPresent([HotkeyBinding].self, forKey: .hotkeys) ?? []
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

    enum CodingKeys: String, CodingKey {
        case windows, bookmarks
        case foldingStates = "folding_states"
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
