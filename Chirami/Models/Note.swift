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

private struct ColorSet {
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

private struct NoteColorDef {
    let background: ColorSet
    let text: ColorSet
    let link: ColorSet
}

enum NoteColor: String, CaseIterable, Codable {
    case yellow, blue, green, pink, purple, gray

    private var def: NoteColorDef {
        switch self {
        case .yellow: return NoteColorDef(
            background: ColorSet(dark: (0.30, 0.28, 0.15), light: (1.0, 0.96, 0.72)),
            text: ColorSet(dark: (0.92, 0.88, 0.65), light: (0.45, 0.38, 0.10)),
            link: ColorSet(dark: (0.95, 0.80, 0.45), light: (0.55, 0.37, 0.10))
        )
        case .blue: return NoteColorDef(
            background: ColorSet(dark: (0.15, 0.22, 0.30), light: (0.72, 0.88, 1.0)),
            text: ColorSet(dark: (0.70, 0.82, 0.95), light: (0.12, 0.25, 0.45)),
            link: ColorSet(dark: (0.60, 0.80, 1.0), light: (0.13, 0.22, 0.55))
        )
        case .green: return NoteColorDef(
            background: ColorSet(dark: (0.15, 0.28, 0.15), light: (0.76, 0.96, 0.76)),
            text: ColorSet(dark: (0.70, 0.92, 0.70), light: (0.15, 0.35, 0.15)),
            link: ColorSet(dark: (0.45, 0.85, 0.76), light: (0.08, 0.35, 0.31))
        )
        case .pink: return NoteColorDef(
            background: ColorSet(dark: (0.30, 0.18, 0.22), light: (1.0, 0.76, 0.84)),
            text: ColorSet(dark: (0.95, 0.72, 0.78), light: (0.50, 0.15, 0.22)),
            link: ColorSet(dark: (1.0, 0.60, 0.69), light: (0.60, 0.15, 0.29))
        )
        case .purple: return NoteColorDef(
            background: ColorSet(dark: (0.22, 0.18, 0.30), light: (0.88, 0.76, 1.0)),
            text: ColorSet(dark: (0.85, 0.75, 0.95), light: (0.30, 0.15, 0.45)),
            link: ColorSet(dark: (0.78, 0.64, 1.0), light: (0.37, 0.15, 0.55))
        )
        case .gray: return NoteColorDef(
            background: ColorSet(dark: (0.25, 0.25, 0.25), light: (0.88, 0.88, 0.88)),
            text: ColorSet(dark: (0.82, 0.82, 0.82), light: (0.25, 0.25, 0.25)),
            link: ColorSet(dark: (0.67, 0.73, 0.82), light: (0.22, 0.26, 0.35))
        )
        }
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
    var displayName: String { rawValue.capitalized }

    var codeColor: NSColor {
        NSColor(name: nil) { appearance in
            switch self {
            case .yellow:
                return appearance.isDark
                    ? NSColor(calibratedRed: 0.22, green: 0.71, blue: 0.30, alpha: 1.0)
                    : NSColor(calibratedRed: 0.20, green: 0.72, blue: 0.28, alpha: 1.0)
            case .blue:
                return appearance.isDark
                    ? NSColor(calibratedRed: 0.30, green: 0.75, blue: 0.95, alpha: 1.0)
                    : NSColor(calibratedRed: 0.10, green: 0.45, blue: 0.80, alpha: 1.0)
            case .green:
                return appearance.isDark
                    ? NSColor(calibratedRed: 0.35, green: 0.88, blue: 0.55, alpha: 1.0)
                    : NSColor(calibratedRed: 0.10, green: 0.52, blue: 0.25, alpha: 1.0)
            case .pink:
                return appearance.isDark
                    ? NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.70, alpha: 1.0)
                    : NSColor(calibratedRed: 0.80, green: 0.15, blue: 0.35, alpha: 1.0)
            case .purple:
                return appearance.isDark
                    ? NSColor(calibratedRed: 0.72, green: 0.55, blue: 0.98, alpha: 1.0)
                    : NSColor(calibratedRed: 0.45, green: 0.15, blue: 0.75, alpha: 1.0)
            case .gray:
                return appearance.isDark
                    ? NSColor(calibratedRed: 0.55, green: 0.75, blue: 0.85, alpha: 1.0)
                    : NSColor(calibratedRed: 0.20, green: 0.40, blue: 0.55, alpha: 1.0)
            }
        }
    }

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
