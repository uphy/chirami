import Foundation

/// Manages content and auto-saving for Ad-hoc Note windows.
/// Used as an ObservableObject to provide a Binding<String> for LivePreviewEditor.
@MainActor
class DisplayContentModel: ObservableObject, EditorStatePreservable {

    @Published var text: String
    let fileURL: URL?
    nonisolated(unsafe) var savedCursorLocation: Int = 0
    nonisolated(unsafe) var savedScrollOffset: CGPoint = .zero
    private var lastSavedContent: String

    init(content: String, fileURL: URL?) {
        self.text = content
        self.fileURL = fileURL
        self.lastSavedContent = content
    }

    /// Save current text to the file if it differs from the last saved content.
    func save() {
        guard let fileURL else { return }
        guard text != lastSavedContent else { return }
        lastSavedContent = text
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
