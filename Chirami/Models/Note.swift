import Foundation
import AppKit
import SwiftUI

enum NotePosition: Equatable {
    case fixed
    case cursor
}

struct PeriodicNoteInfo: Equatable {
    let pathTemplate: String
    let rolloverDelay: TimeInterval
    let templateFile: URL?
    let titlePrefix: String?
}

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
    var autoHide: Bool = false
    var periodicInfo: PeriodicNoteInfo?

    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id && lhs.color == rhs.color && lhs.transparency == rhs.transparency
            && lhs.title == rhs.title && lhs.path == rhs.path && lhs.alwaysOnTop == rhs.alwaysOnTop
            && lhs.hotkey == rhs.hotkey && lhs.fontSize == rhs.fontSize
            && lhs.position == rhs.position && lhs.autoHide == rhs.autoHide
            && lhs.periodicInfo == rhs.periodicInfo
    }
}

// MARK: - NoteColor

private struct ColorSet {
    let dark: (r: CGFloat, g: CGFloat, b: CGFloat)
    let light: (r: CGFloat, g: CGFloat, b: CGFloat)

    var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            let c = appearance.isDark ? dark : light
            return NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0)
        }
    }
}

private struct NoteColorDef {
    let background: ColorSet
    let text: ColorSet
    let link: ColorSet
}

private let colorTable: [NoteColor: NoteColorDef] = [
    .yellow: NoteColorDef(
        background: ColorSet(dark: (0.30, 0.28, 0.15), light: (1.0, 0.96, 0.72)),
        text: ColorSet(dark: (0.92, 0.88, 0.65), light: (0.45, 0.38, 0.10)),
        link: ColorSet(dark: (0.95, 0.78, 0.40), light: (0.55, 0.35, 0.05))
    ),
    .blue: NoteColorDef(
        background: ColorSet(dark: (0.15, 0.22, 0.30), light: (0.72, 0.88, 1.0)),
        text: ColorSet(dark: (0.70, 0.82, 0.95), light: (0.12, 0.25, 0.45)),
        link: ColorSet(dark: (0.55, 0.78, 1.0), light: (0.08, 0.18, 0.55))
    ),
    .green: NoteColorDef(
        background: ColorSet(dark: (0.15, 0.28, 0.15), light: (0.76, 0.96, 0.76)),
        text: ColorSet(dark: (0.70, 0.92, 0.70), light: (0.15, 0.35, 0.15)),
        link: ColorSet(dark: (0.40, 0.85, 0.75), light: (0.05, 0.35, 0.30))
    ),
    .pink: NoteColorDef(
        background: ColorSet(dark: (0.30, 0.18, 0.22), light: (1.0, 0.76, 0.84)),
        text: ColorSet(dark: (0.95, 0.72, 0.78), light: (0.50, 0.15, 0.22)),
        link: ColorSet(dark: (1.0, 0.55, 0.65), light: (0.60, 0.10, 0.25))
    ),
    .purple: NoteColorDef(
        background: ColorSet(dark: (0.22, 0.18, 0.30), light: (0.88, 0.76, 1.0)),
        text: ColorSet(dark: (0.85, 0.75, 0.95), light: (0.30, 0.15, 0.45)),
        link: ColorSet(dark: (0.75, 0.60, 1.0), light: (0.35, 0.10, 0.55))
    ),
    .gray: NoteColorDef(
        background: ColorSet(dark: (0.25, 0.25, 0.25), light: (0.88, 0.88, 0.88)),
        text: ColorSet(dark: (0.82, 0.82, 0.82), light: (0.25, 0.25, 0.25)),
        link: ColorSet(dark: (0.65, 0.72, 0.82), light: (0.20, 0.25, 0.35))
    )
]

enum NoteColor: String, CaseIterable, Codable {
    case yellow, blue, green, pink, purple, gray

    private var def: NoteColorDef { colorTable[self]! }

    var nsColor: NSColor { def.background.nsColor }
    var textColor: NSColor { def.text.nsColor }
    var linkColor: NSColor { def.link.nsColor }
    var displayName: String { rawValue.capitalized }
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
