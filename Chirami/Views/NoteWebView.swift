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
    // Fold lines are applied after content to avoid being wiped by setContent.
    private var pendingFoldLines: [Int]?

    private var currentColorScheme: NoteColorScheme = .yellow
    private var currentIsDark: Bool = false
    private var currentFontName: String?
    private var currentFontSize: Double = 14

    private var initialCursorOffset: Int = 0
    private var initialScrollOffset: Double = 0

    var onContentChanged: ((String) -> Void)?
    var onCursorChanged: ((Int, Int) -> Void)?
    var onScrollChanged: ((Double) -> Void)?
    var onOpenLink: ((URL) -> Void)?
    var onFontSizeChange: ((Int) -> Void)?
    var onPasteImage: ((String) -> Void)?  // dataUrl
    var onFoldChanged: (([Int]) -> Void)?  // 1-based line numbers

    override init(frame frameRect: NSRect) {
        let config = WKWebViewConfiguration()
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        config.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: "chirami-img")

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
        bridge.onCursorChanged = { [weak self] offset, line in
            self?.onCursorChanged?(offset, line)
        }
        bridge.onScrollChanged = { [weak self] offset in
            self?.onScrollChanged?(offset)
        }
        bridge.onOpenLink = { [weak self] url in
            self?.onOpenLink?(url)
        }
        bridge.onFontSizeChange = { [weak self] delta in
            self?.onFontSizeChange?(delta)
        }
        bridge.onPasteImage = { [weak self] dataUrl in
            self?.onPasteImage?(dataUrl)
        }
        bridge.onFoldChanged = { [weak self] lines in
            self?.onFoldChanged?(lines)
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

    func setNotePath(_ path: String) {
        enqueueOrEval("window.chirami.setNotePath(\(jsonString(path)));")
    }

    func insertText(_ text: String) {
        enqueueOrEval("window.chirami.insertText(\(jsonString(text)));")
    }

    func applyFolding(lines: [Int]) {
        guard !lines.isEmpty else { return }
        if !isReady {
            // Store separately so it can be applied after setContent in handleReady()
            pendingFoldLines = lines
            return
        }
        let linesJSON = lines.map(String.init).joined(separator: ",")
        webView.evaluateJavaScript("window.chirami.applyFolding([\(linesJSON)]);", completionHandler: nil)
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

    func setInitialState(cursor: Int, scroll: Double) {
        initialCursorOffset = cursor
        initialScrollOffset = scroll
    }

    func setCursorPosition(offset: Int) {
        enqueueOrEval("window.chirami.setCursorPosition(\(offset));")
    }

    func setScrollPosition(offset: Double) {
        enqueueOrEval("window.chirami.setScrollPosition(\(offset));")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        setTheme(currentColorScheme, isDark: effectiveAppearance.isDark)
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
        // Apply theme/font/notePath before content so ImagePlugin resolves paths correctly
        for script in pendingScripts {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
        pendingScripts.removeAll()
        if let content = pendingContent {
            pendingContent = nil
            evalSetContent(content)
        }
        // Apply folding after content so it is not wiped by setContent
        if let lines = pendingFoldLines {
            pendingFoldLines = nil
            let linesJSON = lines.map(String.init).joined(separator: ",")
            webView.evaluateJavaScript("window.chirami.applyFolding([\(linesJSON)]);", completionHandler: nil)
        }
        applyInitialState()
    }

    private func applyInitialState() {
        if initialCursorOffset > 0 { setCursorPosition(offset: initialCursorOffset) }
        if initialScrollOffset > 0 { setScrollPosition(offset: initialScrollOffset) }
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
        view.onCursorChanged = { [model] offset, _ in
            model.savedCursorLocation = offset
        }
        view.onScrollChanged = { [model] offset in
            model.savedScrollOffset = CGPoint(x: 0, y: offset)
        }
        view.onOpenLink = { url in
            NSWorkspace.shared.open(url)
        }
        view.onFontSizeChange = { [model] delta in
            let newSize = max(8, min(72, Int(model.fontSize) + delta))
            model.fontSize = CGFloat(newSize)
        }
        view.onPasteImage = { [model, weak view] dataUrl in
            guard let view else { return }
            model.handlePastedImage(dataUrl: dataUrl) { markdown in
                view.insertText(markdown)
            }
        }
        view.onFoldChanged = { [model] lines in
            model.updateFoldingState(lines: lines)
        }
        model.focusWebView = { [weak view] in
            view?.focus()
        }
        view.setInitialState(
            cursor: model.savedCursorLocation,
            scroll: model.savedScrollOffset.y
        )
        return view
    }

    func updateNSView(_ nsView: NoteWebView, context: Context) {
        nsView.setContent(model.text)
        nsView.setTheme(model.colorScheme, isDark: nsView.effectiveAppearance.isDark)
        nsView.setFont(name: model.fontName, size: Double(model.fontSize))
        if let notePath = model.notePath {
            nsView.setNotePath(notePath)
        }
        if let foldedLines = model.pendingFoldedLines {
            nsView.applyFolding(lines: foldedLines)
            model.pendingFoldedLines = nil
        }
    }
}
