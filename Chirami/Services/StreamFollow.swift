import Foundation

/// Pure decision logic for stream-note "follow" semantics (tail -f): a newly
/// detected file should replace what's displayed only if the window is
/// visible and the user was already looking at the previous latest file.
/// Extracted out of `NoteWindowController` (see stream-note-mode design
/// decision 4) so it is unit-testable without AppKit windows.
enum StreamFollow {
    /// - Parameters:
    ///   - isVisible: whether the note window is currently visible.
    ///   - displayedFile: the file currently shown in the window.
    ///   - previousLatest: the latest matching file as of the last directory
    ///     rescan, i.e. before the change that triggered this decision.
    /// - Returns: true if the display should auto-advance to the new latest.
    static func shouldFollow(isVisible: Bool, displayedFile: URL, previousLatest: URL?) -> Bool {
        guard isVisible, let previousLatest else { return false }
        return displayedFile.path == previousLatest.path
    }
}
