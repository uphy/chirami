import SwiftUI
import AppKit

/// SwiftUI content view for Ad-hoc Notes using the WebView-based editor.
struct DisplayContentView: View {
    @ObservedObject var model: DisplayContentModel
    let isReadOnly: Bool
    let theme: String?

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
            DisplayWebViewRepresentable(
                model: model,
                isReadOnly: isReadOnly,
                theme: theme
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

    func makeNSView(context: Context) -> NoteWebView {
        let view = NoteWebView(frame: .zero)
        if isReadOnly {
            // Disable editing in CodeMirror itself; read-only windows have no
            // save path, so any input would otherwise be silently lost.
            view.setReadOnly(true)
        } else {
            view.onContentChanged = { [model] text in
                model.text = text
            }
        }
        view.onCursorChanged = { [model] offset, _ in
            model.savedCursorLocation = offset
        }
        view.onScrollChanged = { [model] offset in
            model.savedScrollOffset = CGPoint(x: 0, y: offset)
        }
        view.onOpenLink = { url in
            NSWorkspace.shared.open(url)
        }
        model.setWindowActive = { [weak view] active in
            view?.setWindowActive(active)
        }
        model.getEditorContext = { [weak view] options, completion in
            guard let view else {
                completion(.failure(NSError(domain: "DisplayWebView", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "webView deallocated"])))
                return
            }
            view.getEditorContext(options: options, completion: completion)
        }
        view.setInitialState(
            cursor: model.savedCursorLocation,
            scroll: model.savedScrollOffset.y
        )
        if let fileURL = model.fileURL {
            view.setNotePath(fileURL.path)
        }
        return view
    }

    func updateNSView(_ nsView: NoteWebView, context: Context) {
        nsView.setContent(model.text)
        nsView.setThemeAttribute(theme)
    }
}
