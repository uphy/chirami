import AppKit
import Combine
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

    private var currentFontSize: Double = 14
    private var appliedTheme: String?
    private var hasAppliedTheme: Bool = false

    // Appearance hot-reload state
    private var cancellables = Set<AnyCancellable>()
    private var appliedAppearance: AppearanceConfig?
    private var appliedVariables: [String: String] = [:]
    private var appliedUserCSSContent: String?
    private var userCSSWatcher: FileWatcher?
    private var watchedUserCSSPath: String?

    private var initialCursorOffset: Int = 0
    private var initialScrollOffset: Double = 0

    var onContentChanged: ((String) -> Void)?
    var onCursorChanged: ((Int, Int) -> Void)?
    var onScrollChanged: ((Double) -> Void)?
    var onOpenLink: ((URL) -> Void)?
    var onPasteImage: ((String) -> Void)?  // dataUrl
    var onFoldChanged: (([Int]) -> Void)?  // 1-based line numbers
    /// JS -> Swift transcript dispatch target, forwarded to the bridge.
    /// The bridge holds it weakly; see `NoteWebViewBridge.transcriptEventHandler`.
    var transcriptEventHandler: TranscriptEventHandler? {
        get { bridge.transcriptEventHandler }
        set { bridge.transcriptEventHandler = newValue }
    }
    /// Fires once after the editor is ready and the NSPanel background has been synced
    /// to the theme's `--chirami-bg`. Lets the window controller defer fade-in until the
    /// final theme colour is in place, avoiding a default-yellow flash at startup.
    var onReadyForDisplay: (() -> Void)?
    private var didNotifyReadyForDisplay: Bool = false

    /// True while an overlay (e.g. Excalidraw) is open in the WebView.
    private(set) var overlayVisible: Bool = false

    /// True while the CodeMirror search panel (Cmd+F) is open in the WebView.
    private(set) var searchPanelVisible: Bool = false

    override init(frame frameRect: NSRect) {
        let config = WKWebViewConfiguration()
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        config.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: "chirami-img")

        let userContentController = WKUserContentController()
        config.userContentController = userContentController

        // Inject the built-in CSS at document start (loaded once, reused across all webviews).
        if let script = NoteWebView.defaultCSSScript {
            userContentController.addUserScript(script)
        }

        // Load user CSS file if configured in appearance.cssFile
        let initialUserCSSContent = NoteWebView.readUserCSS(
            path: AppConfig.shared.config.appearance?.cssFile
        )
        if let userCSSContent = initialUserCSSContent,
           let script = NoteWebView.makeStyleScript(from: userCSSContent, id: NoteWebView.userCSSElementID) {
            userContentController.addUserScript(script)
        }

        // Apply appearance.variables as inline style on <html>.
        // Inline style has the highest specificity so it wins over any stylesheet rule
        // (including theme selectors), while Cmd+/- runtime font-size overrides still take
        // effect because they write to the same inline style slot after this script runs.
        let initialVariables = NoteWebView.resolvedVariables(
            AppConfig.shared.config.appearance?.variables ?? [:]
        )
        if !initialVariables.isEmpty {
            if let script = NoteWebView.makeVariablesScript(initialVariables) {
                userContentController.addUserScript(script)
            }
        }

        self.webView = FirstMouseWKWebView(frame: .zero, configuration: config)
        // Suppress the WKWebView background so the native panel background shows through
        self.webView.setValue(false, forKey: "drawsBackground")
        self.webView.underPageBackgroundColor = .clear
        self.bridge = NoteWebViewBridge()
        userContentController.add(bridge, name: "chirami")

        super.init(frame: frameRect)

        self.appliedAppearance = AppConfig.shared.config.appearance
        self.appliedUserCSSContent = initialUserCSSContent
        self.appliedVariables = initialVariables

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
        bridge.onPasteImage = { [weak self] dataUrl in
            guard let self else { return }
            if let onPasteImage = self.onPasteImage {
                onPasteImage(dataUrl)
            } else {
                self.logger.warning("pasteImage received but no callback is wired")
            }
        }
        bridge.onPlainPaste = { [weak self] in
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
            self?.insertText(text)
        }
        bridge.onFoldChanged = { [weak self] lines in
            guard let self else { return }
            if let onFoldChanged = self.onFoldChanged {
                onFoldChanged(lines)
            } else {
                self.logger.warning("foldChanged received but no callback is wired")
            }
        }
        bridge.onOverlayVisibleChanged = { [weak self] visible in
            self?.overlayVisible = visible
        }
        bridge.onSearchPanelVisibleChanged = { [weak self] visible in
            self?.searchPanelVisible = visible
        }
        bridge.onPluginStateRequest = { [weak self] pluginId in
            self?.sendPluginState(pluginId: pluginId)
        }
        bridge.onPluginStateChanged = { pluginId, stateJson in
            PluginStateStore.shared.save(pluginId: pluginId, json: stateJson)
        }

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        startWatchingUserCSS(path: AppConfig.shared.config.appearance?.cssFile)

        // Hot-reload appearance.css_file and appearance.variables on config changes.
        // removeDuplicates avoids re-applying when unrelated config fields change.
        AppConfig.shared.$data
            .map(\.appearance)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] appearance in
                self?.applyAppearanceChanges(appearance)
            }
            .store(in: &cancellables)

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

    func setWindowActive(_ active: Bool) {
        enqueueOrEval("window.chirami.setWindowActive(\(active ? "true" : "false"));")
    }

    /// Toggles CodeMirror read-only mode (EditorState.readOnly + EditorView.editable).
    /// Queued until the editor is ready, like other window.chirami calls.
    func setReadOnly(_ readOnly: Bool) {
        enqueueOrEval("window.chirami.setReadOnly(\(readOnly ? "true" : "false"));")
    }

    func setCapabilities(_ capabilities: NoteWebViewCapabilities) {
        enqueueOrEval("window.chirami.setCapabilities(\(capabilities.json));")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        (window as? NotePanel)?.applyConfiguredAppearance()
        guard isReady else { return }
        DispatchQueue.main.async { [weak self] in
            self?.fetchAndApplyPanelBackground()
        }
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
        enqueueOrEval("window.chirami.setNotePath(\(Self.jsonString(path)));")
    }

    func insertText(_ text: String) {
        enqueueOrEval("window.chirami.insertText(\(Self.jsonString(text)));")
    }

    func transcriptChunk(_ chunk: TranscriptChunkMessage) {
        evaluateTranscriptMethod("transcriptChunk", payload: chunk)
    }

    func transcriptPreviewUpdate(_ preview: TranscriptPreviewMessage) {
        evaluateTranscriptMethod("transcriptPreviewUpdate", payload: preview)
    }

    func transcriptStateChanged(_ state: TranscriptStateMessage) {
        evaluateTranscriptMethod("transcriptStateChanged", payload: state)
    }

    func transcriptLevelUpdate(_ update: TranscriptLevelUpdateMessage) {
        evaluateTranscriptMethod("transcriptLevelUpdate", payload: update)
    }

    func transcriptDevicesList(_ message: TranscriptDevicesListMessage) {
        let selectedValue = message.selectedValue ?? ""
        logger.info(
            "transcriptDevicesList toJS source=\(message.source.rawValue, privacy: .public) selected=\(selectedValue, privacy: .public) count=\(message.devices.count)"
        )
        evaluateTranscriptMethod("transcriptDevicesList", payload: message)
    }

    func transcriptModelState(_ message: TranscriptModelStateMessage) {
        logger.info(
            "transcriptModelState toJS selected=\(message.selectedValue, privacy: .public) count=\(message.models.count)"
        )
        evaluateTranscriptMethod("transcriptModelState", payload: message)
    }

    func transcriptModelDownloadProgress(_ message: TranscriptModelDownloadProgressMessage) {
        evaluateTranscriptMethod("transcriptModelDownloadProgress", payload: message)
    }

    func transcriptError(_ message: TranscriptErrorMessage) {
        evaluateTranscriptMethod("transcriptError", payload: message)
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

    /// Updates the --chirami-font-size CSS variable directly on the html element.
    func setFontSize(_ size: Double) {
        guard size != currentFontSize else { return }
        currentFontSize = size
        enqueueOrEval("document.documentElement.style.setProperty('--chirami-font-size', '\(size)px');")
    }

    /// Injects data-chirami-theme attribute on <html> for per-note theme selection.
    /// nil removes the attribute so CSS :root defaults apply.
    func setThemeAttribute(_ theme: String?) {
        guard !hasAppliedTheme || theme != appliedTheme else { return }
        appliedTheme = theme
        hasAppliedTheme = true
        if let theme {
            enqueueOrEval("document.documentElement.setAttribute('data-chirami-theme', \(Self.jsonString(theme)));")
        } else {
            enqueueOrEval("document.documentElement.removeAttribute('data-chirami-theme');")
        }
        if isReady { fetchAndApplyPanelBackground() }
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

    /// Dispatches a synthetic Escape keydown event into the WebView's JS context.
    /// Used when Swift intercepts ESC but wants JS (e.g. an overlay) to handle it.
    func dispatchEscapeKey() {
        enqueueOrEval("document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}))")
    }

    /// Closes the CodeMirror search panel if it is open. Called when the note
    /// window is hidden so the panel (and its match highlights) do not linger on
    /// the next show.
    func closeSearchPanel() {
        enqueueOrEval("window.chirami.closeSearch();")
    }

    func getEditorContext(options: ContextRequestOptions? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        guard isReady else {
            completion(.failure(NSError(domain: "NoteWebView", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "editor not ready"])))
            return
        }
        let script: String
        if let options {
            do {
                let data = try JSONEncoder().encode(options)
                guard let json = String(data: data, encoding: .utf8) else {
                    completion(.failure(NSError(domain: "NoteWebView", code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "failed to encode context options"])))
                    return
                }
                script = "window.chirami.getEditorContext(\(json))"
            } catch {
                completion(.failure(error))
                return
            }
        } else {
            script = "window.chirami.getEditorContext()"
        }

        webView.evaluateJavaScript(script) { result, error in
            if let error {
                completion(.failure(error))
            } else if let json = result as? String {
                completion(.success(json))
            } else {
                completion(.failure(NSError(domain: "NoteWebView", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "unexpected JS return type"])))
            }
        }
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
        // Apply theme attribute / font size / notePath before content so ImagePlugin resolves paths correctly
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
        setWindowActive(window?.isKeyWindow == true)
        fetchAndApplyPanelBackground()
    }

    /// Reads the computed --chirami-bg value from CSS and applies it to the containing NSPanel.
    /// This keeps the native title bar colour in sync with the WebView background theme.
    /// Also fires `onReadyForDisplay` the first time it completes so the window controller can
    /// safely fade in knowing both the WebView and the NSPanel background reflect the theme.
    private func fetchAndApplyPanelBackground() {
        let js = "getComputedStyle(document.documentElement).getPropertyValue('\(Self.bgVariable)').trim()"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let colorStr = result as? String, !colorStr.isEmpty {
                    if let color = NSColor(cssRGB: colorStr) {
                        self.window?.backgroundColor = color
                    } else {
                        self.logger.warning("Could not parse \(Self.bgVariable, privacy: .public) value: \(colorStr, privacy: .public)")
                    }
                }
                if !self.didNotifyReadyForDisplay {
                    self.didNotifyReadyForDisplay = true
                    self.onReadyForDisplay?()
                }
            }
        }
    }

    private func applyInitialState() {
        if initialCursorOffset > 0 { setCursorPosition(offset: initialCursorOffset) }
        if initialScrollOffset > 0 { setScrollPosition(offset: initialScrollOffset) }
    }

    private func evalSetContent(_ text: String) {
        let escaped = Self.jsonString(text)
        lastSetContent = text
        webView.evaluateJavaScript("window.chirami.setContent(\(escaped));") { [weak self] _, error in
            if let error {
                self?.logger.error("setContent failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func evaluateTranscriptMethod<T: Encodable>(_ method: String, payload: T) {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            logger.error("Failed to encode transcript payload for \(method, privacy: .public)")
            return
        }
        let script = "window.chirami.\(method)(\(json));"
        if !isReady {
            pendingScripts.append(script)
            return
        }
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.error("transcript JS call \(method, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func pluginStateJSON(for pluginId: String) -> String? {
        if pluginId == ExcalidrawLibraryStore.pluginId {
            return ExcalidrawLibraryStore.shared.load()
        }
        return PluginStateStore.shared.load(pluginId: pluginId)
    }

    private func sendPluginState(pluginId: String) {
        let stateArg = pluginStateJSON(for: pluginId).map { Self.jsonString($0) } ?? "null"
        webView.evaluateJavaScript(
            "window.__chiramiPluginReady(\(Self.jsonString(pluginId)), \(stateArg));",
            completionHandler: nil
        )
    }

    // MARK: - Static helpers

    private static let staticLogger = Logger(subsystem: "io.github.uphy.Chirami", category: "NoteWebView")

    /// CSS custom property tracked by the Swift layer for NSPanel background sync.
    fileprivate static let bgVariable = "--chirami-bg"

    /// Font-size variable is owned by `setFontSize` (Cmd+/- runtime control);
    /// `applyVariablesDiff` must not overwrite it.
    private static let fontSizeVariable = "--chirami-font-size"

    /// DOM id assigned to the injected user CSS `<style>` element so it can be diffed on hot-reload.
    fileprivate static let userCSSElementID = "chirami-user-css"

    /// Built-in theme CSS loaded once from the bundle and reused by every webview.
    ///
    /// Loaded from `Bundle.main` (the `.app`'s `Contents/Resources`) — the same
    /// mechanism used for the editor web files — so the resource ships with the
    /// app bundle rather than relying on the SwiftPM resource bundle, which is
    /// not copied into the distributed `.app`.
    private static let defaultCSSScript: WKUserScript? = {
        guard let cssURL = Bundle.main.url(forResource: "chirami-default", withExtension: "css"),
              let css = try? String(contentsOf: cssURL, encoding: .utf8) else {
            staticLogger.error("chirami-default.css not found in bundle")
            return nil
        }
        return makeStyleScript(from: css)
    }()

    /// Encodes a Swift string as a JSON string literal suitable for embedding in a JS expression.
    fileprivate static func jsonString(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode(text),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }

    /// Expands a `~/`-prefixed path to an absolute file URL.
    private static func expandedURL(from path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// Reads the user CSS file referenced by `appearance.css_file`, logging a warning if missing.
    private static func readUserCSS(path: String?) -> String? {
        guard let path else { return nil }
        let url = expandedURL(from: path)
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        staticLogger.warning("cssFile not found or unreadable: \(url.path, privacy: .public)")
        return nil
    }

    /// Resolves variable keys to full CSS custom property names (prepends `--chirami-` when missing).
    private static func resolvedVariables(_ dict: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (k, v) in dict {
            let key = k.hasPrefix("--") ? k : "--chirami-\(k)"
            result[key] = v
        }
        return result
    }

    /// Creates a WKUserScript that injects the given CSS content as a <style> element at document start.
    /// When `id` is non-nil, the element receives that id so it can be located and replaced later.
    private static func makeStyleScript(from cssContent: String, id: String? = nil) -> WKUserScript? {
        let idLine = id.map { "s.id = \(jsonString($0));" } ?? ""
        let js = """
        (function() {
          var s = document.createElement('style');
          \(idLine)
          s.textContent = \(jsonString(cssContent));
          (document.head || document.documentElement).appendChild(s);
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// Creates a WKUserScript that sets CSS custom properties as inline style on <html>.
    /// Keys must already be fully resolved (e.g. `--chirami-bg`).
    private static func makeVariablesScript(_ resolved: [String: String]) -> WKUserScript? {
        guard !resolved.isEmpty else { return nil }
        let statements = resolved.map { key, value in
            "document.documentElement.style.setProperty(\(jsonString(key)), \(jsonString(value)));"
        }
        let js = """
        (function() {
          \(statements.joined(separator: "\n  "))
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    // MARK: - Appearance Hot-Reload

    private func applyAppearanceChanges(_ appearance: AppearanceConfig?) {
        let newPath = appearance?.cssFile
        startWatchingUserCSS(path: newPath)
        applyUserCSSChange(path: newPath)

        let newVars = NoteWebView.resolvedVariables(appearance?.variables ?? [:])
        applyVariablesDiff(new: newVars)
        appliedAppearance = appearance
    }

    private func applyVariablesDiff(new: [String: String]) {
        guard new != appliedVariables else { return }
        var bgAffected = false
        let old = appliedVariables
        // Removed keys
        for key in old.keys where new[key] == nil {
            // Skip font-size: `setFontSize` owns this slot at runtime.
            guard key != Self.fontSizeVariable else { continue }
            enqueueOrEval("document.documentElement.style.removeProperty(\(Self.jsonString(key)));")
            if key == Self.bgVariable { bgAffected = true }
        }
        // Added or changed keys
        for (key, value) in new where old[key] != value {
            guard key != Self.fontSizeVariable else { continue }
            enqueueOrEval("document.documentElement.style.setProperty(\(Self.jsonString(key)), \(Self.jsonString(value)));")
            if key == Self.bgVariable { bgAffected = true }
        }
        appliedVariables = new
        if bgAffected && isReady { fetchAndApplyPanelBackground() }
    }

    private func applyUserCSSChange(path: String?) {
        let newContent = NoteWebView.readUserCSS(path: path)
        guard newContent != appliedUserCSSContent else { return }

        let idJSON = Self.jsonString(NoteWebView.userCSSElementID)
        let removeJS = "{var el=document.getElementById(\(idJSON));if(el)el.remove();}"
        if let content = newContent {
            let js = """
            (function() {
              \(removeJS)
              var s = document.createElement('style');
              s.id = \(idJSON);
              s.textContent = \(Self.jsonString(content));
              (document.head || document.documentElement).appendChild(s);
            })();
            """
            enqueueOrEval(js)
        } else {
            enqueueOrEval("(function(){\(removeJS)})();")
        }

        appliedUserCSSContent = newContent

        // Theme rules in user CSS may affect --chirami-bg; resync the panel background.
        if isReady { fetchAndApplyPanelBackground() }
    }

    private func startWatchingUserCSS(path: String?) {
        guard path != watchedUserCSSPath else { return }
        watchedUserCSSPath = path
        userCSSWatcher = nil
        guard let path else { return }
        let url = NoteWebView.expandedURL(from: path)
        userCSSWatcher = FileWatcher(url: url) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyUserCSSChange(path: AppConfig.shared.config.appearance?.cssFile)
            }
        }
    }
}

// MARK: - Host wiring

extension NoteWebView {
    /// Wires the host-independent editor callbacks, pushes the host's
    /// capabilities to JS, and restores the host's saved editor state.
    ///
    /// Called from both Representables' `makeNSView` so a new editor feature
    /// only needs to be wired here once. Capability-gated callbacks are left
    /// unwired when the capability is off; if JS sends such a message anyway,
    /// the bridge-side warning fires instead of failing silently.
    func wireCommonCallbacks(host: NoteWebViewHost) {
        let capabilities = host.webViewCapabilities
        onContentChanged = { [weak host] text in
            host?.webViewContentChanged(text)
        }
        onCursorChanged = { [weak host] offset, _ in
            host?.savedCursorLocation = offset
        }
        onScrollChanged = { [weak host] offset in
            host?.savedScrollOffset = CGPoint(x: 0, y: offset)
        }
        onOpenLink = { url in
            NSWorkspace.shared.open(url)
        }
        if capabilities.pasteImage {
            onPasteImage = { [weak host, weak self] dataUrl in
                host?.webViewPastedImage(dataUrl: dataUrl) { [weak self] markdown in
                    self?.insertText(markdown + "\n")
                }
            }
        }
        if capabilities.fold {
            onFoldChanged = { [weak host] lines in
                host?.webViewFoldChanged(lines: lines)
            }
        }
        if capabilities.transcript {
            // JS -> Swift via the bridge's weak handler, Swift -> JS via the
            // coordinator's weak sink. Re-wired whenever the WebView is recreated.
            transcriptEventHandler = host.transcriptCoordinator
            host.transcriptCoordinator?.sink = self
        }
        host.setWindowActive = { [weak self] active in
            self?.setWindowActive(active)
        }
        host.getEditorContext = { [weak self] options, completion in
            guard let self else {
                completion(.failure(NSError(domain: "NoteWebView", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "webView deallocated"])))
                return
            }
            self.getEditorContext(options: options, completion: completion)
        }
        setCapabilities(capabilities)
        setInitialState(
            cursor: host.savedCursorLocation,
            scroll: host.savedScrollOffset.y
        )
    }
}

// MARK: - TranscriptMessageSink conformance

/// Declaration-only: the transcript* sender methods are defined in the class
/// body above so `evaluateTranscriptMethod`'s pre-ready queueing is unchanged.
extension NoteWebView: TranscriptMessageSink {}

// MARK: - FirstMouseWKWebView

/// A WKWebView subclass that accepts the first mouse click even when the window is not key.
/// This allows clicks on interactive elements (e.g. checkboxes) to register without requiring
/// a separate click to focus the window first.
private final class FirstMouseWKWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - NoteWebViewRepresentable

struct NoteWebViewRepresentable: NSViewRepresentable {
    @ObservedObject var model: NoteContentModel

    func makeNSView(context: Context) -> NoteWebView {
        let view = NoteWebView(frame: .zero)
        view.wireCommonCallbacks(host: model)
        view.onReadyForDisplay = { [model] in
            model.onWebViewReady?()
        }
        model.focusWebView = { [weak view] in
            view?.focus()
        }
        model.closeSearchPanel = { [weak view] in
            view?.closeSearchPanel()
        }
        return view
    }

    func updateNSView(_ nsView: NoteWebView, context: Context) {
        nsView.setContent(model.text)
        nsView.setFontSize(Double(model.fontSize))
        nsView.setThemeAttribute(model.theme)
        if let notePath = model.notePath {
            nsView.setNotePath(notePath)
        }
        if let foldedLines = model.pendingFoldedLines {
            nsView.applyFolding(lines: foldedLines)
            model.pendingFoldedLines = nil
        }
    }
}

// MARK: - NSColor CSS helpers

private extension NSColor {
    /// Parses a CSS `rgb(R, G, B)` or `rgba(R, G, B, A)` string into an NSColor.
    convenience init?(cssRGB string: String) {
        let s = string.trimmingCharacters(in: .whitespaces)
        let inner: String
        if s.hasPrefix("rgba(") && s.hasSuffix(")") {
            inner = String(s.dropFirst(5).dropLast())
        } else if s.hasPrefix("rgb(") && s.hasSuffix(")") {
            inner = String(s.dropFirst(4).dropLast())
        } else {
            return nil
        }
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3,
              let r = Double(parts[0]),
              let g = Double(parts[1]),
              let b = Double(parts[2]) else { return nil }
        let a = parts.count >= 4 ? (Double(parts[3]) ?? 1.0) : 1.0
        self.init(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
}
