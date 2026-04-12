import SwiftUI
import AppKit

/// SwiftUI content view for Ad-hoc Notes using the WebView-based editor.
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
            DisplayWebViewRepresentable(
                model: model,
                isReadOnly: isReadOnly,
                colorScheme: colorScheme,
                fontSize: fontSize,
                fontName: fontName
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
    let colorScheme: NoteColorScheme
    let fontSize: CGFloat
    let fontName: String?

    func makeNSView(context: Context) -> NoteWebView {
        let view = NoteWebView(frame: .zero)
        if !isReadOnly {
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
        nsView.setTheme(colorScheme, isDark: nsView.effectiveAppearance.isDark)
        nsView.setFont(name: fontName, size: Double(fontSize))
    }
}
