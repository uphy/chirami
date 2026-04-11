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
    private var pendingScripts: [String] = []

    private var currentColorScheme: NoteColorScheme = .yellow
    private var currentIsDark: Bool = false
    private var currentFontName: String?
    private var currentFontSize: Double = 14

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

    func focus() {
        window?.makeFirstResponder(webView)
        enqueueOrEval("window.chirami.focus();")
    }

    func setContent(_ text: String) {
        guard text != lastSetContent else { return }
        if !isReady {
            pendingContent = text
            return
        }
        evalSetContent(text)
    }

    func setTheme(_ colorScheme: NoteColorScheme, isDark: Bool) {
        guard colorScheme != currentColorScheme || isDark != currentIsDark else { return }
        currentColorScheme = colorScheme
        currentIsDark = isDark
        let cssVars = ColorSchemeCSSConverter.cssVariables(for: colorScheme, isDark: isDark)
        enqueueOrEval("window.chirami.setTheme(\(jsonString(cssVars)));")
    }

    func setFont(name: String?, size: Double) {
        guard name != currentFontName || size != currentFontSize else { return }
        currentFontName = name
        currentFontSize = size
        let family = FontCSSConverter.cssFontFamily(from: name)
        enqueueOrEval("window.chirami.setFont(\(jsonString(family)), \(size));")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let isDark = effectiveAppearance.isDark
        currentIsDark = isDark
        let cssVars = ColorSchemeCSSConverter.cssVariables(for: currentColorScheme, isDark: isDark)
        enqueueOrEval("window.chirami.setTheme(\(jsonString(cssVars)));")
    }

    private func enqueueOrEval(_ script: String) {
        if !isReady {
            pendingScripts.append(script)
            return
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func handleReady() {
        isReady = true
        if let content = pendingContent {
            pendingContent = nil
            evalSetContent(content)
        }
        for script in pendingScripts {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
        pendingScripts.removeAll()
    }

    private func evalSetContent(_ text: String) {
        let escaped = jsonString(text)
        lastSetContent = text
        webView.evaluateJavaScript("window.chirami.setContent(\(escaped));") { [weak self] _, error in
            if let error {
                self?.logger.error("setContent failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func jsonString(_ text: String) -> String {
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
        nsView.setTheme(model.colorScheme, isDark: nsView.effectiveAppearance.isDark)
        nsView.setFont(name: model.fontName, size: Double(model.fontSize))
    }
}
