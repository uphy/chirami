import SwiftUI
import AppKit

/// SwiftUI content view for Ad-hoc Notes using the WebView-based editor.
struct DisplayContentView: View {
    @ObservedObject var model: DisplayContentModel
    let isReadOnly: Bool
    let theme: String?
    /// Background opacity; applied to the background only so text stays opaque.
    var backgroundAlpha: Double = 1

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
            DisplayWebViewRepresentable(
                model: model,
                isReadOnly: isReadOnly,
                theme: theme,
                backgroundAlpha: backgroundAlpha
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.text) { _, _ in
            model.save()
        }
    }
}

private struct DisplayWebViewRepresentable: NSViewRepresentable {
    @ObservedObject var model: DisplayContentModel
    let isReadOnly: Bool
    let theme: String?
    let backgroundAlpha: Double

    func makeNSView(context: Context) -> NoteWebView {
        let view = NoteWebView(frame: .zero)
        if isReadOnly {
            // Disable editing in CodeMirror itself; read-only windows have no
            // save path, so any input would otherwise be silently lost.
            // (The model also ignores content changes as a backstop.)
            view.setReadOnly(true)
        }
        view.wireCommonCallbacks(host: model)
        if let fileURL = model.fileURL {
            view.setNotePath(fileURL.path)
        }
        return view
    }

    func updateNSView(_ nsView: NoteWebView, context: Context) {
        nsView.setContent(model.text)
        nsView.setThemeAttribute(theme)
        nsView.setBackgroundAlpha(backgroundAlpha)
    }
}
