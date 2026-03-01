import Foundation

/// Manages auto-saving content to a file for Ad-hoc Note windows.
/// Prevents redundant writes using lastSavedContent comparison.
class DisplayContentModel {

    private let fileURL: URL
    private var lastSavedContent: String

    init(fileURL: URL, initialContent: String) {
        self.fileURL = fileURL
        self.lastSavedContent = initialContent
    }

    /// Save `text` to the file if it differs from the last saved content.
    func save(text: String) {
        guard text != lastSavedContent else { return }
        lastSavedContent = text
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
