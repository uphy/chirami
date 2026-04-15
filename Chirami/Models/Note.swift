import Foundation
import AppKit

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
    var theme: String?
    var transparency: Double = 0.9
    var alwaysOnTop: Bool = true
    var hotkey: String?
    var position: NotePosition = .fixed
    var periodicInfo: PeriodicNoteInfo?
    var attachmentsDir: URL?

    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id && lhs.theme == rhs.theme && lhs.transparency == rhs.transparency
            && lhs.title == rhs.title && lhs.path == rhs.path && lhs.alwaysOnTop == rhs.alwaysOnTop
            && lhs.hotkey == rhs.hotkey
            && lhs.position == rhs.position
            && lhs.periodicInfo == rhs.periodicInfo
            && lhs.attachmentsDir == rhs.attachmentsDir
    }
}
