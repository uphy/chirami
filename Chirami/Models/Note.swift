import Foundation
import AppKit
import SwiftUI

enum NotePosition: Equatable {
    case fixed
    case cursor
}

/// Metadata for a Periodic Note (a Registered Note with a date-template path).
struct PeriodicNoteInfo: Equatable {
    let pathTemplate: String
    let rolloverDelay: TimeInterval
    let templateFile: URL?
    let titlePrefix: String?
}

/// A Registered Note — a note defined in config.yaml's `notes[]` array.
/// Can be either a Static Note (fixed path) or a Periodic Note (date-template path).
struct Note: Identifiable, Equatable {
    let id: String
    var path: URL
    var title: String
    var color: NoteColor
    var transparency: Double = 0.9
    var fontSize: CGFloat = 14
    var alwaysOnTop: Bool = true
    var hotkey: String?
    var position: NotePosition = .fixed
    var periodicInfo: PeriodicNoteInfo?
    var attachmentsDir: URL?

    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id && lhs.color == rhs.color && lhs.transparency == rhs.transparency
            && lhs.title == rhs.title && lhs.path == rhs.path && lhs.alwaysOnTop == rhs.alwaysOnTop
            && lhs.hotkey == rhs.hotkey && lhs.fontSize == rhs.fontSize
            && lhs.position == rhs.position
            && lhs.periodicInfo == rhs.periodicInfo
            && lhs.attachmentsDir == rhs.attachmentsDir
    }
}

// MARK: - NoteColor

struct ColorSet {
    let dark: (r: CGFloat, g: CGFloat, b: CGFloat)
    let light: (r: CGFloat, g: CGFloat, b: CGFloat)

    var nsColor: NSColor {
        nsColor(alpha: 1.0)
    }

    func nsColor(alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let c = appearance.isDark ? self.dark : self.light
            return NSColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)
        }
    }
}

struct NoteColorDef {
    let background: ColorSet
    let text: ColorSet
    let link: ColorSet
    let code: ColorSet
}

struct NoteColor: Codable, Equatable, Hashable {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    init?(rawValue: String) {
        self.name = rawValue
    }

    var rawValue: String { name }

    static let yellow = NoteColor("yellow")
    static let blue   = NoteColor("blue")
    static let green  = NoteColor("green")
    static let pink   = NoteColor("pink")
    static let purple = NoteColor("purple")
    static let gray   = NoteColor("gray")

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.name = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }

    private var def: NoteColorDef {
        ThemeRegistry.shared.definition(for: self)
    }

    var nsColor: NSColor { def.background.nsColor }
    var textColor: NSColor { def.text.nsColor }
    var linkColor: NSColor { def.link.nsColor }
    var selectionColor: NSColor {
        let t = def.text
        return NSColor(name: nil) { appearance in
            let c = appearance.isDark ? t.dark : t.light
            let alpha: CGFloat = appearance.isDark ? 0.3 : 0.15
            return NSColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)
        }
    }
    var codeColor: NSColor { def.code.nsColor }

    static let codeBackgroundColor: NSColor = NSColor(name: nil) { appearance in
        NSColor.labelColor.withAlphaComponent(appearance.isDark ? 0.08 : 0.07)
    }
}

// MARK: - NSAppearance

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - NSColor → SwiftUI Color

extension NSColor {
    var swiftUI: Color { Color(self) }
}
