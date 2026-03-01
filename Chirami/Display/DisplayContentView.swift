import SwiftUI

/// SwiftUI content view for Ad-hoc Notes, reusing LivePreviewEditor for Markdown rendering.
struct DisplayContentView: View {
    @ObservedObject var model: DisplayContentModel
    let isReadOnly: Bool
    let noteColor: NoteColor
    let fontSize: CGFloat

    var body: some View {
        LivePreviewEditor(
            text: $model.text,
            backgroundColor: noteColor.nsColor,
            noteColor: noteColor,
            fontSize: fontSize,
            noteURL: model.fileURL,
            isReadOnly: isReadOnly
        )
        .onChange(of: model.text) { _, _ in
            model.save()
        }
    }
}
