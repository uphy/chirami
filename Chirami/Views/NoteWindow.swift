import AppKit
import SwiftUI
import Combine
import os

// MARK: - NoteWindowController

/// Manages a single note window: position/size persistence, transparency, always-on-top.
@MainActor
class NoteWindowController: NSWindowController, NSWindowDelegate, EditorContextProvider {
    private(set) var note: Note
    private let noteStore = NoteStore.shared
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "NoteWindowController")
    private var fileWatcher: FileWatcher?
    private var contentModel: NoteContentModel
    private var cancellables = Set<AnyCancellable>()
    private var isShowingToday: Bool = true
    private var isPinned: Bool
    private var isFadingOut: Bool = false
    private var fadeOutToken: Int = 0
    /// True once the WebView has signalled readiness for display at least once.
    /// Subsequent `show()` calls fade in immediately.
    private var hasBecomeReadyOnce: Bool = false
    /// Set when `show()` runs before the WebView is ready; the fade-in runs when ready fires.
    private var pendingFadeIn: Bool = false
    /// Safety timer that forces fade-in if the WebView never signals readiness.
    private var fadeInTimeoutTask: Task<Void, Never>?
    private var transcriptLevelMonitors: [Int: TranscriptLevelMonitor] = [:]
    nonisolated(unsafe) private var warpEventMonitor: Any?
    nonisolated(unsafe) private var shortcutEventMonitor: Any?

    var isVisible: Bool { window?.isVisible ?? false }

    init(note: Note) {
        self.note = note
        self.isPinned = NoteStore.shared.isPinned(note)
        self.contentModel = NoteContentModel(note: note)

        let savedState = NoteStore.shared.windowState(for: note)
        let frame = CGRect(
            origin: savedState?.cgPoint ?? CGPoint(x: 100, y: 200),
            size: savedState?.cgSize ?? CGSize(width: 300, height: 400)
        )

        let panel = NotePanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = note.title
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .visible
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = note.alwaysOnTop ? .floating : .normal
        panel.alphaValue = note.transparency
        panel.backgroundColor = NoteWindowController.defaultPanelBackground
        panel.isRestorable = false

        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setupCloseButtonHover()
        panel.centerTitle()

        super.init(window: panel)
        panel.delegate = self
        configureTranscriptCallbacks()
        panel.onHideRequest = { [weak self] in
            self?.hide()
        }
        contentModel.onWebViewReady = { [weak self] in
            self?.handleWebViewReady()
        }

        if note.periodicInfo != nil {
            panel.setupNavigationButtons(
                target: self,
                prevAction: #selector(navigatePrevious),
                nextAction: #selector(navigateNext),
                todayAction: #selector(navigateToToday)
            )
            updateNavigationButtons()
        }

        panel.setupPinButton { [weak self] in self?.togglePinAction() }
        panel.updatePinState(isPinned: isPinned)
        panel.applyConfiguredAppearance()

        let rootView = NoteContentView(model: contentModel, noteId: note.id, onTogglePin: { [weak self] in self?.togglePinAction() })
            .environmentObject(NoteStore.shared)
        applyContentView(rootView, to: panel)

        setupFileWatcher()

        let noteId = note.id
        NoteStore.shared.$notes
            .dropFirst()
            .sink { notes in
                guard let updated = notes.first(where: { $0.id == noteId }) else { return }
                Task { @MainActor [weak self] in
                    self?.applyNoteUpdate(updated)
                }
            }
            .store(in: &cancellables)

        // Use a local event monitor instead of sendEvent override so warp keys are
        // captured even when WKWebView holds first responder focus.
        warpEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            let warpFlags = AppConfig.shared.data.warpModifierFlags
            let activeFlags = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.function, .numericPad])
            guard activeFlags == warpFlags else { return event }
            if let char = event.charactersIgnoringModifiers?.first,
               ["h", "j", "k", "l"].contains(char) {
                self.warpTo(key: char)
                return nil
            }
            if let mapped = Self.warpArrowMap[event.keyCode] {
                self.warpTo(key: mapped)
                return nil
            }
            return event
        }

        // Intercept window-level shortcuts at the NSEvent level to prevent WKWebView
        // from generating a system beep for these key combinations.
        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            let flags = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.function, .numericPad])
            guard let chars = event.charactersIgnoringModifiers else { return event }
            // Cmd+= or Cmd+Shift+= (Cmd++) → font size up
            if chars == "=", flags == .command || flags == [.command, .shift] {
                self.handleFontSizeChange(delta: 1)
                return nil
            }
            // Cmd+- → font size down
            if chars == "-", flags == .command {
                self.handleFontSizeChange(delta: -1)
                return nil
            }
            let warpFlags = AppConfig.shared.data.warpModifierFlags
            if flags == warpFlags {
                if chars == "=" {
                    self.handleWindowScaleChange(scale: Self.windowScaleStep)
                    return nil
                }
                if chars == "-" {
                    self.handleWindowScaleChange(scale: 1 / Self.windowScaleStep)
                    return nil
                }
            }
            return event
        }
    }

    deinit {
        if let monitor = warpEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = shortcutEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        fadeInTimeoutTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Default panel background color matching the CSS default (yellow theme).
    /// MUST stay in sync with `--chirami-bg` in `Chirami/Resources/chirami-default.css`.
    /// Used as the pre-WebView panel color so the window doesn't flash a mismatched
    /// hue before `fetchAndApplyPanelBackground` reads the computed CSS value.
    static let defaultPanelBackground: NSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 77/255, green: 71/255, blue: 38/255, alpha: 1.0)    // --chirami-bg dark
            : NSColor(red: 255/255, green: 245/255, blue: 184/255, alpha: 1.0) // --chirami-bg light
    }

    // MARK: - Visibility

    func showIfNeeded() {
        let visible = noteStore.isVisible(note)
        if visible {
            showWindow(nil)
        }
    }

    func show() {
        guard let panel = window as? NotePanel else { return }

        // Switch to today's note if the date has changed while the window was hidden
        if note.periodicInfo != nil, isShowingToday {
            navigateToTodayIfNeeded()
        }

        // Cancel in-flight fade-out
        isFadingOut = false
        fadeOutToken += 1

        if !panel.isVisible {
            panel.alphaValue = 0
            if note.position == .cursor {
                showAtCursor()
            } else {
                showWindow(nil)
            }
        } else {
            // Mid-fade-out: window is still visible, reset alpha for fade-in
            panel.alphaValue = 0
        }

        if NotePanel.startupMode {
            // Startup path: show without stealing keyboard focus.
            panel.orderFront(nil)
        } else {
            // Always make key explicitly. showWindow(nil) calls orderFront (not
            // makeKeyAndOrderFront) for floating panels, so becomeKey never fires.
            panel.makeKeyAndOrderFront(nil)
        }

        noteStore.setVisible(true, for: note)

        if hasBecomeReadyOnce {
            performFadeIn()
        } else {
            // Defer fade-in until the WebView reports ready so the panel doesn't flash
            // the default theme colour before the configured theme is applied.
            pendingFadeIn = true
            scheduleFadeInTimeout()
        }
    }

    private func performFadeIn() {
        guard let panel = window as? NotePanel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = note.transparency
        }
    }

    private func handleWebViewReady() {
        hasBecomeReadyOnce = true
        fadeInTimeoutTask?.cancel()
        fadeInTimeoutTask = nil
        if pendingFadeIn {
            pendingFadeIn = false
            performFadeIn()
        }
    }

    /// Forces fade-in after a grace period so a broken WebView never leaves the window invisible.
    private func scheduleFadeInTimeout() {
        fadeInTimeoutTask?.cancel()
        fadeInTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.pendingFadeIn else { return }
            self.pendingFadeIn = false
            self.logger.warning("WebView ready timeout; forcing fade-in")
            self.performFadeIn()
        }
    }

    private func showAtCursor() {
        guard let window = window else { return }

        let cursorLocation = NSEvent.mouseLocation
        let windowSize = window.frame.size

        let screen = screenForCursor() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let margins = currentWarpMargin()

        let origin = CGPoint(x: cursorLocation.x - windowSize.width / 2, y: cursorLocation.y - windowSize.height / 2)
        let clamped = clampToScreen(origin: origin, windowSize: windowSize, visibleFrame: visibleFrame, margins: margins)

        window.setFrameOrigin(clamped)
        showWindow(nil)
        window.orderFront(nil)
    }

    private func screenForCursor() -> NSScreen? {
        let cursorLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens where NSMouseInRect(cursorLocation, screen.frame, false) {
            return screen
        }
        return NSScreen.main
    }

    func hide() {
        guard let panel = window as? NotePanel else { return }

        saveEditorState()

        // Cancel any fade-in still waiting on WebView ready
        pendingFadeIn = false
        fadeInTimeoutTask?.cancel()
        fadeInTimeoutTask = nil

        isFadingOut = true
        let token = fadeOutToken
        let targetTransparency = note.transparency

        noteStore.setVisible(false, for: note)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isFadingOut, self.fadeOutToken == token else { return }
                self.isFadingOut = false
                panel.orderOut(nil)
                panel.alphaValue = targetTransparency  // Restore for next show()
            }
        })
    }

    func saveEditorState() {
        AppState.shared.updateEditorState(
            for: note.id,
            cursorPosition: contentModel.savedCursorLocation,
            scrollOffset: contentModel.savedScrollOffset
        )
    }

    /// Returns the current editor state for batch persistence.
    var editorStateSnapshot: (noteId: String, cursorPosition: Int, scrollOffset: CGPoint) {
        (note.id, contentModel.savedCursorLocation, contentModel.savedScrollOffset)
    }

    func toggle() {
        if isVisible {
            if window?.isKeyWindow == true {
                hide()
            } else {
                window?.makeKeyAndOrderFront(nil)
            }
        } else {
            show()
        }
    }

    // MARK: - Note updates

    private func applyNoteUpdate(_ updated: Note) {
        guard let panel = window as? NotePanel else { return }
        let pathChanged = updated.path != note.path

        note = updated

        if pathChanged {
            reloadContentForNavigation()
            if !isFadingOut {
                panel.alphaValue = updated.transparency
            }
            panel.level = updated.alwaysOnTop ? .floating : .normal
            return
        }

        // Skip alpha update during fade-out to avoid interrupting animation
        if !isFadingOut {
            panel.alphaValue = updated.transparency
        }
        panel.title = updated.title
        panel.level = updated.alwaysOnTop ? .floating : .normal
        contentModel.applyNoteMetadata(updated)
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        contentModel.setWindowActive?(true)
        contentModel.focusWebView?()
        WindowManager.shared.noteWindowDidBecomeKey(self)
    }

    func getEditorContext(options: ContextRequestOptions? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        guard let getter = contentModel.getEditorContext else {
            completion(.failure(NSError(domain: "ContextHandler", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "editor not ready"])))
            return
        }
        getter(options, completion)
    }

    func windowDidResignKey(_ notification: Notification) {
        contentModel.setWindowActive?(false)
        guard !isPinned, isVisible else { return }
        contentModel.save()
        hide()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = window else { return }
        noteStore.saveWindowState(
            for: note,
            position: window.frame.origin,
            size: window.frame.size,
            visible: false
        )
    }

    func windowDidMove(_ notification: Notification) {
        if note.position != .cursor {
            saveWindowState()
        }
    }

    func windowDidResize(_ notification: Notification) {
        if note.position == .cursor {
            // Save size only: read existing position from state
            guard let window = window else { return }
            let existingPosition = noteStore.windowState(for: note)?.cgPoint ?? window.frame.origin
            noteStore.saveWindowState(
                for: note,
                position: existingPosition,
                size: window.frame.size,
                visible: isVisible
            )
        } else {
            saveWindowState()
        }
    }

    private func saveWindowState() {
        guard let window = window else { return }
        noteStore.saveWindowState(
            for: note,
            position: window.frame.origin,
            size: window.frame.size,
            visible: isVisible
        )
    }

    // MARK: - Font Size

    private func handleFontSizeChange(delta: Int) {
        let newSize = max(8, min(72, Int(contentModel.fontSize) + delta))
        contentModel.fontSize = CGFloat(newSize)
    }

    // MARK: - Window Scaling

    private static let windowScaleStep: CGFloat = 1.1
    private static let minWindowSize = CGSize(width: 220, height: 180)

    private func handleWindowScaleChange(scale: CGFloat) {
        guard let window = window else { return }
        let screen = screenForWindow() ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let margins = currentWarpMargin()

        let currentSize = window.frame.size
        guard currentSize.width > 0, currentSize.height > 0 else { return }

        let availableWidth = max(Self.minWindowSize.width, visibleFrame.width - margins.left - margins.right)
        let availableHeight = max(Self.minWindowSize.height, visibleFrame.height - margins.top - margins.bottom)
        let minScale = max(
            Self.minWindowSize.width / currentSize.width,
            Self.minWindowSize.height / currentSize.height
        )
        let maxScale = min(
            availableWidth / currentSize.width,
            availableHeight / currentSize.height
        )
        let appliedScale: CGFloat
        if scale >= 1 {
            appliedScale = min(scale, maxScale)
            guard appliedScale > 1 else { return }
        } else {
            appliedScale = max(scale, minScale)
            guard appliedScale < 1 else { return }
        }

        let newSize = CGSize(
            width: round(currentSize.width * appliedScale),
            height: round(currentSize.height * appliedScale)
        )
        guard abs(newSize.width - currentSize.width) >= 1 || abs(newSize.height - currentSize.height) >= 1 else {
            return
        }

        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let origin = CGPoint(
            x: center.x - newSize.width / 2,
            y: center.y - newSize.height / 2
        )
        let clampedOrigin = clampToScreen(
            origin: origin,
            windowSize: newSize,
            visibleFrame: visibleFrame,
            margins: margins
        )
        let newFrame = CGRect(origin: clampedOrigin, size: newSize)
        window.setFrame(newFrame, display: true, animate: true)
    }

    // MARK: - Keyboard Warp

    private static let warpArrowMap: [UInt16: Character] = [123: "h", 124: "l", 125: "j", 126: "k"]

    /// Warp the window to the adjacent grid position in the given HJKL direction, cycling at edges.
    func warpTo(key: Character) {
        guard let window = window else { return }
        let screen = screenForWindow() ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let margins = currentWarpMargin()

        let center = CGPoint(
            x: window.frame.midX,
            y: window.frame.midY
        )
        let (col, row) = inferGridPosition(center: center, visibleFrame: visibleFrame, margins: margins)
        let (newCol, newRow) = applyMove(key: key, col: col, row: row)
        let origin = gridOrigin(
            col: newCol,
            row: newRow,
            windowSize: window.frame.size,
            visibleFrame: visibleFrame,
            margins: margins
        )
        let clampedOrigin = clampToScreen(
            origin: origin,
            windowSize: window.frame.size,
            visibleFrame: visibleFrame,
            margins: margins
        )
        let newFrame = CGRect(origin: clampedOrigin, size: window.frame.size)
        window.setFrame(newFrame, display: true, animate: true)
    }

    /// Returns the screen whose visible area contains the window's center point.
    private func screenForWindow() -> NSScreen? {
        guard let window = window else { return NSScreen.main }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        for screen in NSScreen.screens where screen.frame.contains(center) {
            return screen
        }
        return NSScreen.main
    }

    private func currentWarpMargin() -> ResolvedWarpMargin {
        AppConfig.shared.data.resolvedWarpMargin
    }

    private func clampToScreen(origin: CGPoint, windowSize: CGSize, visibleFrame: CGRect, margins: ResolvedWarpMargin) -> CGPoint {
        var x = origin.x
        var y = origin.y

        let minX = visibleFrame.minX + margins.left
        let maxX = visibleFrame.maxX - windowSize.width - margins.right
        let minY = visibleFrame.minY + margins.bottom
        let maxY = visibleFrame.maxY - windowSize.height - margins.top

        if windowSize.width + margins.left + margins.right >= visibleFrame.width {
            x = visibleFrame.midX - windowSize.width / 2
        } else {
            x = min(max(x, minX), maxX)
        }

        if windowSize.height + margins.top + margins.bottom >= visibleFrame.height {
            y = visibleFrame.midY - windowSize.height / 2
        } else {
            y = min(max(y, minY), maxY)
        }

        return CGPoint(x: x, y: y)
    }

    /// Maps the window center to the nearest 3x3 grid cell using band detection.
    /// col: 0=left, 1=center, 2=right / row: 0=bottom, 1=center, 2=top (NSWindow bottom-left origin)
    private func inferGridPosition(
        center: CGPoint,
        visibleFrame: CGRect,
        margins: ResolvedWarpMargin
    ) -> (col: Int, row: Int) {
        let warpBounds = CGRect(
            x: visibleFrame.minX + margins.left,
            y: visibleFrame.minY + margins.bottom,
            width: max(0, visibleFrame.width - margins.left - margins.right),
            height: max(0, visibleFrame.height - margins.top - margins.bottom)
        )

        let col: Int
        if warpBounds.width <= 0 {
            col = 1
        } else {
            col = Int(min(2, max(0, (center.x - warpBounds.minX) / (warpBounds.width / 3))))
        }

        let row: Int
        if warpBounds.height <= 0 {
            row = 1
        } else {
            row = Int(min(2, max(0, (center.y - warpBounds.minY) / (warpBounds.height / 3))))
        }
        return (col, row)
    }

    /// Applies an HJKL move to grid coordinates with cyclic wrapping.
    private func applyMove(key: Character, col: Int, row: Int) -> (col: Int, row: Int) {
        switch key {
        case "h": return ((col + 2) % 3, row)
        case "l": return ((col + 1) % 3, row)
        case "k": return (col, (row + 1) % 3)
        case "j": return (col, (row + 2) % 3)
        default:  return (col, row)
        }
    }

    /// Calculates the window origin for a grid cell using display-edge gaps.
    private func gridOrigin(
        col: Int,
        row: Int,
        windowSize: CGSize,
        visibleFrame: CGRect,
        margins: ResolvedWarpMargin
    ) -> CGPoint {
        let x: CGFloat
        switch col {
        case 0:  x = visibleFrame.minX + margins.left
        case 2:  x = visibleFrame.maxX - windowSize.width - margins.right
        default: x = visibleFrame.midX - windowSize.width / 2
        }
        let y: CGFloat
        switch row {
        case 0:  y = visibleFrame.minY + margins.bottom
        case 2:  y = visibleFrame.maxY - windowSize.height - margins.top
        default: y = visibleFrame.midY - windowSize.height / 2
        }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Pin

    @objc func togglePinAction() {
        isPinned.toggle()
        noteStore.setPinned(isPinned, for: note)
        (window as? NotePanel)?.updatePinState(isPinned: isPinned)
    }

    // MARK: - Periodic Note Navigation

    @objc func navigatePrevious() {
        guard let files = periodicMatchingFiles(),
              let prev = PeriodicFileNavigator.previousFile(from: note.path, in: files) else { return }
        navigateToFile(prev)
    }

    @objc func navigateNext() {
        guard let files = periodicMatchingFiles(),
              let next = PeriodicFileNavigator.nextFile(from: note.path, in: files) else { return }
        navigateToFile(next)
    }

    private func periodicMatchingFiles() -> [URL]? {
        guard let info = note.periodicInfo else { return nil }
        let baseDir = PathTemplateResolver.extractBaseDirectory(from: info.pathTemplate)
        guard let baseDirURL = resolveTemplatePath(baseDir) else { return nil }
        let relativeTemplate = String(info.pathTemplate.dropFirst(baseDir.count))
        return PeriodicFileNavigator.listMatchingFiles(template: relativeTemplate, baseDirectory: baseDirURL)
    }

    /// Navigate to today's periodic note only if the date has changed.
    /// Skips model recreation when the path hasn't changed (preserves cursor/scroll).
    private func navigateToTodayIfNeeded() {
        resolveAndNavigateToToday(force: false)
    }

    @objc func navigateToToday() {
        resolveAndNavigateToToday(force: true)
    }

    private func resolveAndNavigateToToday(force: Bool) {
        guard let info = note.periodicInfo else { return }
        let config = NoteConfig(path: info.pathTemplate, template: info.templateFile?.path)
        let date = noteStore.logicalDate(rolloverDelay: info.rolloverDelay)
        guard let newNote = noteStore.resolvePeriodicNote(from: config, for: date) else { return }
        if !force {
            guard newNote.path.path != note.path.path else { return }
        }
        navigateToFile(newNote.path)
        isShowingToday = true
        updateNavigationButtons()
    }

    func handleRollover(_ newNote: Note) {
        guard isShowingToday else { return }
        note.path = newNote.path
        note.title = newNote.title
        reloadContentForNavigation()
    }

    private func navigateToFile(_ url: URL) {
        note.path = url
        // Update title
        if let info = note.periodicInfo {
            let fileName = url.deletingPathExtension().lastPathComponent
            if let prefix = info.titlePrefix {
                note.title = "\(prefix) — \(fileName)"
            } else {
                note.title = fileName
            }
        }
        isShowingToday = false
        // Check if navigated file is actually today's file
        if let info = note.periodicInfo {
            let todayPath = PathTemplateResolver.resolve(info.pathTemplate, for: noteStore.logicalDate(rolloverDelay: info.rolloverDelay))
            if let todayURL = resolveTemplatePath(todayPath), todayURL.path == url.path {
                isShowingToday = true
            }
        }
        reloadContentForNavigation()
    }

    private func reloadContentForNavigation() {
        if !FileManager.default.fileExists(atPath: note.path.path) {
            noteStore.writeContent("", to: note)
        }

        contentModel = NoteContentModel(note: note)
        configureTranscriptCallbacks()
        contentModel.onWebViewReady = { [weak self] in
            self?.handleWebViewReady()
        }
        let rootView = NoteContentView(model: contentModel, noteId: note.id, onTogglePin: { [weak self] in self?.togglePinAction() })
            .environmentObject(NoteStore.shared)
        if let panel = window as? NotePanel {
            applyContentView(rootView, to: panel)
        }

        // Update panel title
        (window as? NotePanel)?.title = note.title

        // Restart file watcher
        setupFileWatcher()

        updateNavigationButtons()
    }

    private func updateNavigationButtons() {
        guard let panel = window as? NotePanel,
              let files = periodicMatchingFiles() else { return }
        let hasPrev = PeriodicFileNavigator.previousFile(from: note.path, in: files) != nil
        let hasNext = PeriodicFileNavigator.nextFile(from: note.path, in: files) != nil
        panel.updateNavigationState(hasPrevious: hasPrev, hasNext: hasNext, isToday: isShowingToday)
    }

    private func resolveTemplatePath(_ path: String) -> URL? {
        if path.hasPrefix("~/") {
            return FileManager.realHomeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }

    // MARK: - File watching

    private func setupFileWatcher() {
        // Create the file if it doesn't exist
        if !FileManager.default.fileExists(atPath: note.path.path) {
            noteStore.writeContent("", to: note)
        }

        fileWatcher = FileWatcher(url: note.path) { [weak self] in
            Task { @MainActor [weak self] in
                self?.reloadContent()
            }
        }
    }

    private func reloadContent() {
        let newContent = noteStore.readContent(of: note)
        contentModel.reloadIfNeeded(newContent)
    }

    private func applyContentView<V: View>(_ rootView: V, to panel: NotePanel) {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        debugLogContentViewIfNeeded(panel: panel, hostingView: hostingView)
    }

    private func debugLogContentViewIfNeeded(panel: NotePanel, hostingView: NSView) {
        guard ProcessInfo.processInfo.environment["CHIRAMI_DEBUG_TITLEBAR"] == "1" else { return }
        logger.debug("[Content] title=\(panel.title, privacy: .public) frame=\(String(describing: panel.frame), privacy: .public) contentLayoutRect=\(String(describing: panel.contentLayoutRect), privacy: .public)")
        logger.debug("[Content] hosting frame=\(String(describing: hostingView.frame), privacy: .public) wantsLayer=\(hostingView.wantsLayer) layerBg=\(String(describing: hostingView.layer?.backgroundColor), privacy: .public)")
        if let contentView = panel.contentView {
            logger.debug("[Content] contentView type=\(String(describing: type(of: contentView)), privacy: .public) frame=\(String(describing: contentView.frame), privacy: .public)")
            if let superview = contentView.superview {
                logger.debug("[Content] contentSuperview type=\(String(describing: type(of: superview)), privacy: .public) frame=\(String(describing: superview.frame), privacy: .public)")
            }
        }
    }

    private func configureTranscriptCallbacks() {
        contentModel.onTranscriptDeviceSelect = { [weak self] selection in
            guard let self else { return }
            switch selection.source {
            case .mic:
                AppState.shared.updateTranscriptDeviceCache(lastMic: selection.value, lastSystemSource: nil)
            case .system:
                AppState.shared.updateTranscriptDeviceCache(lastMic: nil, lastSystemSource: selection.value)
            }
            self.logger.info("transcriptDeviceSelect source=\(selection.source.rawValue, privacy: .public) value=\(selection.value, privacy: .public)")
            self.sendTranscriptDevicesList(
                for: TranscriptDevicesRequestMessage(
                    range: selection.range,
                    source: selection.source
                )
            )
        }
        contentModel.onTranscriptRecordStart = { [weak self] message in
            guard let self else { return }
            self.logger.info("transcriptRecordStart blockFrom=\(message.range.blockFrom) blockTo=\(message.range.blockTo)")
            let session = self.makeTranscriptSession(for: message)
            Task {
                await self.stopTranscriptLevelMonitor(for: message.range)
                await TranscriptSessionRegistry.shared.start(session)
            }
        }
        contentModel.onTranscriptRecordPause = { [weak self] range in
            self?.logger.info("transcriptRecordPause blockFrom=\(range.blockFrom) blockTo=\(range.blockTo)")
            Task {
                await TranscriptSessionRegistry.shared.pause(range: range)
            }
        }
        contentModel.onTranscriptRecordResume = { [weak self] range in
            self?.logger.info("transcriptRecordResume blockFrom=\(range.blockFrom) blockTo=\(range.blockTo)")
            Task {
                await TranscriptSessionRegistry.shared.resume(range: range)
            }
        }
        contentModel.onTranscriptRecordStop = { [weak self] range in
            self?.logger.info("transcriptRecordStop blockFrom=\(range.blockFrom) blockTo=\(range.blockTo)")
            Task {
                await self?.stopTranscriptLevelMonitor(for: range)
                await TranscriptSessionRegistry.shared.stop(range: range)
            }
        }
        contentModel.onTranscriptRecordClear = { [weak self] range in
            self?.logger.info("transcriptRecordClear blockFrom=\(range.blockFrom) blockTo=\(range.blockTo)")
            Task {
                await self?.stopTranscriptLevelMonitor(for: range)
                await TranscriptSessionRegistry.shared.clear(range: range)
            }
        }
        contentModel.onTranscriptLevelMonitorStart = { [weak self] message in
            guard let self else { return }
            Task {
                await self.startTranscriptLevelMonitor(for: message)
            }
        }
        contentModel.onTranscriptLevelMonitorStop = { [weak self] range in
            guard let self else { return }
            Task {
                await self.stopTranscriptLevelMonitor(for: range)
            }
        }
        contentModel.onTranscriptDevicesRequest = { [weak self] request in
            guard let self else { return }
            self.logger.debug("transcriptDevicesRequest source=\(request.source.rawValue, privacy: .public) blockFrom=\(request.range.blockFrom)")
            self.sendTranscriptDevicesList(for: request)
        }
        contentModel.onTranscriptModelRequest = { [weak self] request in
            guard let self else { return }
            self.logger.debug("transcriptModelRequest blockFrom=\(request.range.blockFrom)")
            self.sendTranscriptModelState(for: request.range)
        }
        contentModel.onTranscriptModelSelect = { [weak self] selection in
            guard let self else { return }
            guard let selectedModel = try? SherpaOnnxModelStore.shared.resolvedCatalogModel(for: selection.value) else {
                self.logger.warning("transcriptModelSelect ignored unsupported value=\(selection.value, privacy: .public)")
                self.sendTranscriptModelState(for: selection.range)
                return
            }
            AppState.shared.setTranscriptModel(selectedModel.identifier)
            self.sendTranscriptModelState(for: selection.range)
        }
    }

    private func makeTranscriptSession(for message: TranscriptRecordStartMessage) -> TranscriptSession {
        let transcriptConfig = AppConfig.shared.transcriptConfig
        let availableMicDevices = AudioDeviceEnumerator.audioInputDevices()
        let defaultMicDevice = AudioDeviceEnumerator.defaultAudioInputDevice()
        let resolvedMicDevice = TranscriptDeviceResolver.resolveMicSelection(
            blockSelection: message.micDevice,
            configuredValue: transcriptConfig.devices.mic,
            availableDevices: availableMicDevices,
            defaultDevice: defaultMicDevice
        )
        let availableSystemProcesses = AudioProcessEnumerator.runningOutputProcesses()
        let resolvedSystem = TranscriptDeviceResolver.resolveSystemSelection(
            blockSelection: message.systemDevice,
            configuredValue: transcriptConfig.devices.system,
            availableProcesses: availableSystemProcesses
        )
        let resolvedPIDs = resolvedSystem.processes.map(\.pid).description
        logger.info(
            "transcript device resolution mic.requested=\(message.micDevice.value, privacy: .public) mic.resolved=\(resolvedMicDevice.value, privacy: .public) system.requested=\(message.systemDevice.value, privacy: .public) system.resolved=\(resolvedSystem.selection.value, privacy: .public) resolvedPIDs=\(resolvedPIDs, privacy: .public)"
        )
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendChunk = { [weak self] chunk in
            self?.contentModel.transcriptSendChunk?(chunk)
        }
        callbacks.sendPreview = { [weak self] preview in
            self?.contentModel.transcriptSendPreview?(preview)
        }
        callbacks.sendState = { [weak self] state in
            self?.contentModel.transcriptSendState?(state)
        }
        callbacks.sendLevel = { [weak self] update in
            self?.contentModel.transcriptSendLevel?(update)
        }
        callbacks.sendModelDownloadProgress = { [weak self] progress in
            self?.contentModel.transcriptSendModelDownloadProgress?(progress)
        }
        callbacks.sendError = { [weak self] error in
            self?.contentModel.transcriptSendError?(error)
        }

        let context = TranscriptSessionContext(
            range: message.range,
            modelLabel: transcriptModelLabel(),
            micEnabled: resolvedMicDevice.value != "off",
            micDeviceLabel: resolvedMicDevice.label,
            systemDeviceLabel: resolvedSystem.selection.label,
            labels: transcriptConfig.labels
        )

        let transcriptionEngine = makeTranscriptionEngine()
        let transcriptionEngineFactory = makeTranscriptionEngineFactory()

        return TranscriptSession(
            context: context,
            callbacks: callbacks,
            transcriptionEngine: transcriptionEngine,
            transcriptionEngineFactory: transcriptionEngineFactory,
            systemProcesses: resolvedSystem.processes
        )
    }

    private func startTranscriptLevelMonitor(for message: TranscriptLevelMonitorStartMessage) async {
        await stopTranscriptLevelMonitor(for: message.range)

        let transcriptConfig = AppConfig.shared.transcriptConfig
        let availableMicDevices = AudioDeviceEnumerator.audioInputDevices()
        let defaultMicDevice = AudioDeviceEnumerator.defaultAudioInputDevice()
        let resolvedMicDevice = TranscriptDeviceResolver.resolveMicSelection(
            blockSelection: message.micDevice,
            configuredValue: transcriptConfig.devices.mic,
            availableDevices: availableMicDevices,
            defaultDevice: defaultMicDevice
        )
        let availableSystemProcesses = AudioProcessEnumerator.runningOutputProcesses()
        let resolvedSystem = TranscriptDeviceResolver.resolveSystemSelection(
            blockSelection: message.systemDevice,
            configuredValue: transcriptConfig.devices.system,
            availableProcesses: availableSystemProcesses
        )

        let monitor = TranscriptLevelMonitor(
            range: message.range,
            micEnabled: resolvedMicDevice.value != "off",
            systemProcesses: resolvedSystem.processes
        ) { [weak self] update in
            self?.contentModel.transcriptSendLevel?(update)
        }
        transcriptLevelMonitors[message.range.blockFrom] = monitor
        await monitor.start()
    }

    private func stopTranscriptLevelMonitor(for range: TranscriptBlockRange) async {
        guard let monitor = transcriptLevelMonitors.removeValue(forKey: range.blockFrom) else {
            return
        }
        await monitor.stop()
    }

    private struct ConfiguredTranscriptModel: Sendable {
        let identifier: String
        let label: String
        let detail: String?
        let language: String?
        let kind: SherpaOnnxModelKind
        let supportedLanguages: [String]
        let installed: Bool
        let installedSizeBytes: Int64?
    }

    private func configuredTranscriptModel() -> ConfiguredTranscriptModel? {
        let transcriptConfig = AppConfig.shared.transcriptConfig
        let modelStore = SherpaOnnxModelStore.shared
        let requestedIdentifier = AppState.shared.state.transcriptModel ?? defaultModelIdentifier()
        let resolvedCatalogModel =
            (try? modelStore.resolvedCatalogModel(for: requestedIdentifier)) ??
            (try? modelStore.resolvedCatalogModel(for: defaultModelIdentifier()))
        guard let resolvedCatalogModel else { return nil }

        return ConfiguredTranscriptModel(
            identifier: resolvedCatalogModel.identifier,
            label: resolvedCatalogModel.label,
            detail: resolvedCatalogModel.detail,
            language: transcriptConfig.language,
            kind: resolvedCatalogModel.kind,
            supportedLanguages: resolvedCatalogModel.supportedLanguages,
            installed: modelStore.modelExists(for: resolvedCatalogModel.identifier),
            installedSizeBytes: modelStore.installedSizeBytes(for: resolvedCatalogModel.identifier)
        )
    }

    private func transcriptModelKindLabel(_ kind: SherpaOnnxModelKind) -> String {
        switch kind {
        case .senseVoice:
            return "SenseVoice"
        case .nemoCTC:
            return "NeMo CTC"
        }
    }

    private func transcriptModelLabel() -> String {
        configuredTranscriptModel()?.label ?? "Configured model"
    }

    private func defaultModelIdentifier() -> String {
        SherpaOnnxModelStore.defaultModelIdentifier
    }

    private func sendTranscriptModelState(for range: TranscriptBlockRange) {
        guard let currentModel = configuredTranscriptModel() else { return }
        let options = SherpaOnnxModelStore.shared.builtInModels().map { model in
            TranscriptDeviceOptionMessage(
                value: model.identifier,
                label: model.label,
                detail: model.detail,
                active: model.identifier == currentModel.identifier
            )
        }
        contentModel.transcriptSendModelState?(
            TranscriptModelStateMessage(
                range: range,
                modelLabel: currentModel.label,
                selectedValue: currentModel.identifier,
                models: options,
                metadata: TranscriptModelMetadataMessage(
                    detail: currentModel.detail,
                    kindLabel: transcriptModelKindLabel(currentModel.kind),
                    configuredLanguage: currentModel.language,
                    supportedLanguages: currentModel.supportedLanguages,
                    installed: currentModel.installed,
                    installedSizeBytes: currentModel.installedSizeBytes
                )
            )
        )
    }

    private func makeTranscriptionEngine() -> TranscriptionEngine? {
        guard let model = configuredTranscriptModel() else {
            return nil
        }

        let modelStore = SherpaOnnxModelStore.shared
        guard modelStore.modelExists(for: model.identifier) else {
            logger.info("transcript sherpa engine unavailable until model exists locally: \(model.identifier, privacy: .public)")
            return nil
        }

        let modelFolder = modelStore.resolvedModelURL(for: model.identifier)
        let lexicon = configuredTranscriptLexicon()
        return SherpaOnnxEngine(
            modelFolder: modelFolder,
            modelKind: model.kind,
            language: model.language,
            hotwords: lexicon?.lexicon.hotwordsPayload
        )
    }

    private func makeTranscriptionEngineFactory() -> TranscriptTranscriptionEngineFactory? {
        guard let model = configuredTranscriptModel() else {
            return nil
        }

        guard !SherpaOnnxModelStore.shared.modelExists(for: model.identifier) else {
            return nil
        }

        let hotwords = configuredTranscriptLexicon()?.lexicon.hotwordsPayload

        return { [logger] progress in
            logger.info("transcript sherpa model download start: \(model.identifier, privacy: .public)")
            let modelFolder = try await SherpaOnnxModelStore.shared.downloadModel(id: model.identifier) {
                receivedBytes,
                totalBytes,
                fractionCompleted,
                stage in
                progress(receivedBytes, totalBytes, fractionCompleted, stage)
            }
            logger.info("transcript sherpa model download finished: \(model.identifier, privacy: .public)")
            progress(0, -1, 1, .preparing)
            return SherpaOnnxEngine(
                modelFolder: modelFolder,
                modelKind: model.kind,
                language: model.language,
                hotwords: hotwords
            )
        }
    }

    private func configuredTranscriptLexicon() -> LoadedTranscriptLexicon? {
        do {
            let loaded = try loadTranscriptLexicon(
                from: AppConfig.shared.transcriptConfig,
                configDirectory: AppConfig.shared.configDirectoryURL
            )
            if let loaded, !loaded.lexicon.sttHotwords.isEmpty {
                logger.info("transcript lexicon loaded entries=\(loaded.lexicon.sttHotwords.count) path=\(loaded.url.path, privacy: .public)")
            }
            return loaded
        } catch {
            logger.warning("transcript lexicon load failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func sendTranscriptDevicesList(for request: TranscriptDevicesRequestMessage) {
        let selectedValue = resolvedTranscriptDeviceSelection(for: request.source)
        let devices: [TranscriptDeviceOptionMessage]

        switch request.source {
        case .mic:
            devices = micDeviceOptions(selectedValue: selectedValue)
        case .system:
            devices = systemDeviceOptions(selectedValue: selectedValue)
        }

        let message = TranscriptDevicesListMessage(
            range: request.range,
            source: request.source,
            devices: devices,
            selectedValue: selectedValue
        )
        logger.info(
            "transcriptDevicesList source=\(request.source.rawValue, privacy: .public) selected=\(selectedValue, privacy: .public) count=\(devices.count)"
        )
        contentModel.transcriptSendDevicesList?(message)
    }

    private func resolvedTranscriptDeviceSelection(for source: TranscriptSource) -> String {
        let transcriptConfig = AppConfig.shared.transcriptConfig
        let candidate: String?

        switch source {
        case .mic:
            candidate = AppState.shared.state.lastMic ?? transcriptConfig.devices.mic
        case .system:
            candidate = AppState.shared.state.lastSystemSource ?? transcriptConfig.devices.system
        }

        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return source == .mic ? "default" : "all"
    }

    private func micDeviceOptions(selectedValue: String) -> [TranscriptDeviceOptionMessage] {
        let inputDevices = AudioDeviceEnumerator.audioInputDevices()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let defaultDevice = AudioDeviceEnumerator.defaultAudioInputDevice()
        let deviceValues = Set(inputDevices.map(\.uniqueID))
        let normalizedSelectedValue = selectedValue == "off" ? "off" : selectedValue
        var options: [TranscriptDeviceOptionMessage] = []

        if normalizedSelectedValue != "default" &&
            normalizedSelectedValue != "off" &&
            !deviceValues.contains(normalizedSelectedValue) {
            options.append(
                TranscriptDeviceOptionMessage(
                    value: normalizedSelectedValue,
                    label: normalizedSelectedValue,
                    detail: "Unavailable",
                    active: true
                )
            )
        }

        options.append(
            TranscriptDeviceOptionMessage(
                value: "default",
                label: "Default",
                detail: defaultDevice?.name ?? "System default",
                active: normalizedSelectedValue == "default"
            )
        )

        options.append(contentsOf: inputDevices.map { device in
            TranscriptDeviceOptionMessage(
                value: device.uniqueID,
                label: device.name,
                detail: device.uniqueID == defaultDevice?.uniqueID ? "System default" : nil,
                active: device.uniqueID == normalizedSelectedValue
            )
        })

        return options
    }

    private func systemDeviceOptions(selectedValue: String) -> [TranscriptDeviceOptionMessage] {
        let processes = AudioProcessEnumerator.runningOutputProcesses()
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
        let processValues = Set(processes.map(\.transcriptValue))
        let normalizedSelectedValue = selectedValue == "auto" ? "all" : selectedValue
        var options: [TranscriptDeviceOptionMessage] = [
            TranscriptDeviceOptionMessage(
                value: "all",
                label: "All System Audio",
                detail: "Capture all active system audio",
                active: normalizedSelectedValue == "all"
            )
        ]

        if normalizedSelectedValue != "all" && normalizedSelectedValue != "off" && !processValues.contains(normalizedSelectedValue) {
            options.append(
                TranscriptDeviceOptionMessage(
                    value: normalizedSelectedValue,
                    label: normalizedSelectedValue,
                    detail: "Unavailable",
                    active: true
                )
            )
        }

        options.append(contentsOf: processes.map { process in
            TranscriptDeviceOptionMessage(
                value: process.transcriptValue,
                label: process.displayLabel,
                detail: process.transcriptDetail,
                active: process.transcriptValue == normalizedSelectedValue
            )
        })

        return options
    }
}

// MARK: - NoteContentModel

/// Shared state between NoteWindowController and NoteContentView.
@MainActor
class NoteContentModel: ObservableObject {
    @Published var text: String = ""
    @Published var fontSize: CGFloat = 14
    @Published var theme: String?
    nonisolated(unsafe) var savedCursorLocation: Int = 0
    nonisolated(unsafe) var savedScrollOffset: CGPoint = .zero
    var focusWebView: (() -> Void)?
    var setWindowActive: ((Bool) -> Void)?
    var getEditorContext: ((ContextRequestOptions?, @escaping (Result<String, Error>) -> Void) -> Void)?
    /// Fires once after the WebView is ready and its panel background matches the theme.
    /// The window controller uses this to defer the initial fade-in and avoid a yellow flash.
    var onWebViewReady: (() -> Void)?
    /// Resolved file path of the note (used by image widget for relative path resolution).
    var notePath: String?
    /// Folded line numbers to apply on next WebView update (cleared after applying).
    var pendingFoldedLines: [Int]?
    var transcriptSendChunk: ((TranscriptChunkMessage) -> Void)?
    var transcriptSendPreview: ((TranscriptPreviewMessage) -> Void)?
    var transcriptSendState: ((TranscriptStateMessage) -> Void)?
    var transcriptSendLevel: ((TranscriptLevelUpdateMessage) -> Void)?
    var transcriptSendDevicesList: ((TranscriptDevicesListMessage) -> Void)?
    var transcriptSendModelState: ((TranscriptModelStateMessage) -> Void)?
    var transcriptSendModelDownloadProgress: ((TranscriptModelDownloadProgressMessage) -> Void)?
    var transcriptSendError: ((TranscriptErrorMessage) -> Void)?
    var onTranscriptRecordStart: ((TranscriptRecordStartMessage) -> Void)?
    var onTranscriptRecordPause: ((TranscriptBlockRange) -> Void)?
    var onTranscriptRecordResume: ((TranscriptBlockRange) -> Void)?
    var onTranscriptRecordStop: ((TranscriptBlockRange) -> Void)?
    var onTranscriptRecordClear: ((TranscriptBlockRange) -> Void)?
    var onTranscriptLevelMonitorStart: ((TranscriptLevelMonitorStartMessage) -> Void)?
    var onTranscriptLevelMonitorStop: ((TranscriptBlockRange) -> Void)?
    var onTranscriptDevicesRequest: ((TranscriptDevicesRequestMessage) -> Void)?
    var onTranscriptDeviceSelect: ((TranscriptDeviceSelectionMessage) -> Void)?
    var onTranscriptModelRequest: ((TranscriptModelRequestMessage) -> Void)?
    var onTranscriptModelSelect: ((TranscriptModelSelectionMessage) -> Void)?
    private var note: Note
    private let imagePasteService = ImagePasteService()
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "NoteContentModel")
    private var isSaving = false
    private var isReloading = false
    private var lastSavedContent: String = ""

    init(note: Note) {
        self.note = note
        self.theme = note.theme
        self.notePath = note.path.path
        let content = NoteStore.shared.readContent(of: note)
        text = content
        lastSavedContent = content

        // Restore editor state from persisted window state
        if let state = AppState.shared.windowState(for: note.id) {
            savedCursorLocation = state.cursorPosition ?? 0
            savedScrollOffset = state.scrollCGPoint ?? .zero
        }

        // Restore fold state
        let foldingState = AppState.shared.foldingState(for: note.path.path)
        if !foldingState.foldedLines.isEmpty {
            pendingFoldedLines = Array(foldingState.foldedLines).sorted()
        }
    }

    func save() {
        guard !isSaving, !isReloading, text != lastSavedContent else { return }
        isSaving = true
        lastSavedContent = text
        NoteStore.shared.writeContent(text, to: note)
        isSaving = false
    }

    func reloadIfNeeded(_ newContent: String) {
        guard !isSaving, newContent != text else { return }
        isReloading = true
        lastSavedContent = newContent
        text = newContent
        isReloading = false
    }

    func applyNoteMetadata(_ updated: Note) {
        note = updated
        theme = updated.theme
        notePath = updated.path.path
    }

    /// Decodes a data URL, saves the image to the attachments directory, and calls completion with the Markdown text.
    func handlePastedImage(dataUrl: String, completion: @escaping (String) -> Void) {
        guard let commaIndex = dataUrl.firstIndex(of: ",") else { return }
        let base64 = String(dataUrl[dataUrl.index(after: commaIndex)...])
        guard let imageData = Data(base64Encoded: base64),
              let image = NSImage(data: imageData) else {
            logger.error("Failed to decode pasted image data")
            return
        }

        let noteConfig = AppConfig.shared.config.notes.first { nc in
            nc.resolvedPath == note.path.path
        }
        let attachmentsDir = noteConfig?.resolveAttachmentsDir(
            noteURL: note.path,
            isPeriodicNote: note.periodicInfo != nil,
            pathTemplate: note.periodicInfo?.pathTemplate
        ) ?? note.path.deletingLastPathComponent().appendingPathComponent("attachments")

        let result = imagePasteService.save(image: image, to: attachmentsDir, noteURL: note.path)
        switch result {
        case .success(let pasteResult):
            logger.info("Saved pasted image: \(pasteResult.fileURL.path, privacy: .public)")
            completion(pasteResult.markdownText)
        case .failure(let error):
            logger.error("Failed to save pasted image: \(error, privacy: .public)")
        }
    }

    /// Persists the current folding state when notified by the WebView.
    func updateFoldingState(lines: [Int]) {
        let notePath = note.path.path
        AppState.shared.updateFoldingState(for: notePath) { fs in
            fs.foldedLines = Set(lines)
        }
    }
}

// MARK: - NoteContentView

struct NoteContentView: View {
    @ObservedObject var model: NoteContentModel
    let noteId: String
    var onTogglePin: (() -> Void)?
    @EnvironmentObject private var noteStore: NoteStore

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
            NoteWebViewRepresentable(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.text) { _, _ in
            model.save()
        }
    }
}
