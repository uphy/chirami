import Foundation
import AppKit

struct Note: Identifiable, Equatable {
    let id: String
    var path: URL
    var title: String
    var color: NoteColor
    var transparency: Double = 0.9
    var fontSize: CGFloat = 14
    var alwaysOnTop: Bool = true
    var hotkey: String? = nil

    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id && lhs.color == rhs.color && lhs.transparency == rhs.transparency && lhs.title == rhs.title && lhs.path == rhs.path && lhs.alwaysOnTop == rhs.alwaysOnTop && lhs.hotkey == rhs.hotkey
    }
}

enum NoteColor: String, CaseIterable, Codable {
    case yellow, blue, green, pink, purple, gray

    var nsColor: NSColor {
        switch self {
        case .yellow:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.30, green: 0.28, blue: 0.15, alpha: 1.0)
                    : NSColor(red: 1.0,  green: 0.96, blue: 0.72, alpha: 1.0)
            }
        case .blue:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.15, green: 0.22, blue: 0.30, alpha: 1.0)
                    : NSColor(red: 0.72, green: 0.88, blue: 1.0,  alpha: 1.0)
            }
        case .green:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.15, green: 0.28, blue: 0.15, alpha: 1.0)
                    : NSColor(red: 0.76, green: 0.96, blue: 0.76, alpha: 1.0)
            }
        case .pink:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.30, green: 0.18, blue: 0.22, alpha: 1.0)
                    : NSColor(red: 1.0,  green: 0.76, blue: 0.84, alpha: 1.0)
            }
        case .purple:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.22, green: 0.18, blue: 0.30, alpha: 1.0)
                    : NSColor(red: 0.88, green: 0.76, blue: 1.0,  alpha: 1.0)
            }
        case .gray:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1.0)
                    : NSColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1.0)
            }
        }
    }

    var textColor: NSColor {
        switch self {
        case .yellow:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.92, green: 0.88, blue: 0.65, alpha: 1.0)
                    : NSColor(red: 0.45, green: 0.38, blue: 0.10, alpha: 1.0)
            }
        case .blue:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.70, green: 0.82, blue: 0.95, alpha: 1.0)
                    : NSColor(red: 0.12, green: 0.25, blue: 0.45, alpha: 1.0)
            }
        case .green:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.70, green: 0.92, blue: 0.70, alpha: 1.0)
                    : NSColor(red: 0.15, green: 0.35, blue: 0.15, alpha: 1.0)
            }
        case .pink:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.95, green: 0.72, blue: 0.78, alpha: 1.0)
                    : NSColor(red: 0.50, green: 0.15, blue: 0.22, alpha: 1.0)
            }
        case .purple:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.85, green: 0.75, blue: 0.95, alpha: 1.0)
                    : NSColor(red: 0.30, green: 0.15, blue: 0.45, alpha: 1.0)
            }
        case .gray:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1.0)
                    : NSColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1.0)
            }
        }
    }

    var linkColor: NSColor {
        switch self {
        case .yellow:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.95, green: 0.78, blue: 0.40, alpha: 1.0)
                    : NSColor(red: 0.55, green: 0.35, blue: 0.05, alpha: 1.0)
            }
        case .blue:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.55, green: 0.78, blue: 1.0, alpha: 1.0)
                    : NSColor(red: 0.08, green: 0.18, blue: 0.55, alpha: 1.0)
            }
        case .green:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.40, green: 0.85, blue: 0.75, alpha: 1.0)
                    : NSColor(red: 0.05, green: 0.35, blue: 0.30, alpha: 1.0)
            }
        case .pink:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 1.0, green: 0.55, blue: 0.65, alpha: 1.0)
                    : NSColor(red: 0.60, green: 0.10, blue: 0.25, alpha: 1.0)
            }
        case .purple:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.75, green: 0.60, blue: 1.0, alpha: 1.0)
                    : NSColor(red: 0.35, green: 0.10, blue: 0.55, alpha: 1.0)
            }
        case .gray:
            return NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(red: 0.65, green: 0.72, blue: 0.82, alpha: 1.0)
                    : NSColor(red: 0.20, green: 0.25, blue: 0.35, alpha: 1.0)
            }
        }
    }

    var displayName: String {
        switch self {
        case .yellow: return "Yellow"
        case .blue:   return "Blue"
        case .green:  return "Green"
        case .pink:   return "Pink"
        case .purple: return "Purple"
        case .gray:   return "Gray"
        }
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
