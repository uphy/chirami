import AppKit
import WebKit
import SwiftUI
import os

// MARK: - NoteWebView

@MainActor
final class NoteWebView: NSView {
    private let webView: WKWebView
    private let bridge: NoteWebViewBridge
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "NoteWebView")

    private var pendingContent: String?
    private var lastSetContent: String?
    private var isReady: Bool = false

    var onContentChanged: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        let config = WKWebViewConfiguration()
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        let userContentController = WKUserContentController()
        config.userContentController = userContentController

        self.webView = WKWebView(frame: .zero, configuration: config)
        // Suppress the WKWebView background so the SwiftUI background shows through
        self.webView.setValue(false, forKey: "drawsBackground")
        self.webView.underPageBackgroundColor = .clear
        self.bridge = NoteWebViewBridge()
        userContentController.add(bridge, name: "chirami")

        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Reinforce transparency at the layer level (needed on macOS 26+)
        webView.wantsLayer = true
        webView.layer?.isOpaque = false
        webView.layer?.backgroundColor = .clear

        bridge.onReady = { [weak self] in self?.handleReady() }
        bridge.onContentChanged = { [weak self] text in
            // Track JS-originated content to suppress the echo-back in setContent
            self?.lastSetContent = text
            self?.onContentChanged?(text)
        }

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        loadEditor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadEditor() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "editor") else {
            logger.error("editor/index.html not found in bundle")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func setContent(_ text: String) {
        guard text != lastSetContent else { return }
        if !isReady {
            pendingContent = text
            return
        }
        evalSetContent(text)
    }

    private func handleReady() {
        isReady = true
        if let content = pendingContent {
            pendingContent = nil
            evalSetContent(content)
        }
    }

    private func evalSetContent(_ text: String) {
        let escaped = escapeForJS(text)
        lastSetContent = text
        webView.evaluateJavaScript("window.chirami.setContent(\(escaped));") { [weak self] _, error in
            if let error {
                self?.logger.error("setContent failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func escapeForJS(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode(text),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }
}

// MARK: - NoteWebViewRepresentable

struct NoteWebViewRepresentable: NSViewRepresentable {
    @ObservedObject var model: NoteContentModel

    func makeNSView(context: Context) -> NoteWebView {
        let view = NoteWebView(frame: .zero)
        view.onContentChanged = { [model] text in
            model.text = text
        }
        return view
    }

    func updateNSView(_ nsView: NoteWebView, context: Context) {
        nsView.setContent(model.text)
    }
}
