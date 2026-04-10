import SwiftUI

/// SwiftUI content view for Ad-hoc Notes, reusing LivePreviewEditor for Markdown rendering.
struct DisplayContentView: View {
    @ObservedObject var model: DisplayContentModel
    let isReadOnly: Bool
    let colorScheme: NoteColorScheme
    let fontSize: CGFloat
    let fontName: String?

    var body: some View {
        ZStack {
            Color(nsColor: colorScheme.nsColor)
                .ignoresSafeArea()
            LivePreviewEditor(
                text: $model.text,
                backgroundColor: colorScheme.nsColor,
                colorScheme: colorScheme,
                fontSize: fontSize,
                fontName: fontName,
                noteURL: model.fileURL,
                isReadOnly: isReadOnly,
                editorState: model
            )
        }
        .onChange(of: model.text) { _, _ in
            model.save()
        }
    }
}
