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
    /// Transcript domain logic for this window. Strong `let`: the coordinator
    /// is referenced only weakly everywhere else (model, bridge, sink), so this
    /// is the single reference keeping it alive.
    private let transcriptCoordinator = TranscriptCoordinator()
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
        wireContentModel()
        panel.onHideRequest = { [weak self] in
            self?.hide()
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

        // Reset transient editor UI so it does not linger on the next show.
        // closeSearchPanel is a no-op when the search panel is already closed.
        contentModel.closeSearchPanel?()

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
        transcriptCoordinator.stopAllLevelMonitors()
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

        // The old document's level monitors are keyed by its block positions;
        // the new WebView can never send levelMonitorStop for them, so stop them here.
        transcriptCoordinator.stopAllLevelMonitors()

        contentModel = NoteContentModel(note: note)
        wireContentModel()
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

    /// Wires the current content model to this controller. Must be called
    /// whenever `contentModel` is (re)created (init and navigation reload) so
    /// the transcript coordinator and readiness callback are never left unset.
    private func wireContentModel() {
        contentModel.transcriptCoordinator = transcriptCoordinator
        contentModel.onWebViewReady = { [weak self] in
            self?.handleWebViewReady()
        }
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
    /// Closes the CodeMirror search panel if open. Invoked when the note window
    /// is hidden so the search bar does not linger on the next show.
    var closeSearchPanel: (() -> Void)?
    var setWindowActive: ((Bool) -> Void)?
    var getEditorContext: ((ContextRequestOptions?, @escaping (Result<String, Error>) -> Void) -> Void)?
    /// Fires once after the WebView is ready and its panel background matches the theme.
    /// The window controller uses this to defer the initial fade-in and avoid a yellow flash.
    var onWebViewReady: (() -> Void)?
    /// Resolved file path of the note (used by image widget for relative path resolution).
    var notePath: String?
    /// Folded line numbers to apply on next WebView update (cleared after applying).
    var pendingFoldedLines: [Int]?
    /// Transcript domain coordinator owned by the window controller. Weak: the
    /// controller owns both this model and the coordinator; this reference only
    /// lets the Representable reach the coordinator when wiring the WebView.
    weak var transcriptCoordinator: TranscriptCoordinator?
    private var note: Note
    private let imagePasteService = ImagePasteService()
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "NoteContentModel")
    /// The content most recently loaded from or written to disk.
    /// Used to distinguish self-echo file events (from our own atomic writes)
    /// from genuine external changes.
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
        guard text != lastSavedContent else { return }
        NoteStore.shared.writeContent(text, to: note)
        lastSavedContent = text
    }

    func reloadIfNeeded(_ newContent: String) {
        // Self-echo of our own save (atomic write fires the file watcher):
        // the disk content matches what we last wrote, so skip deterministically.
        guard newContent != lastSavedContent else { return }
        guard newContent != text else {
            // Disk already matches the local text; just mark it as saved.
            lastSavedContent = newContent
            return
        }
        // Genuine external change. If there are unsaved local edits, do not
        // silently overwrite them; keep the local content and warn.
        guard text == lastSavedContent else {
            logger.warning("External change to \(self.note.path.path, privacy: .public) conflicts with unsaved local edits; keeping local content")
            return
        }
        lastSavedContent = newContent
        text = newContent
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

extension NoteContentModel: NoteWebViewHost {
    var webViewCapabilities: NoteWebViewCapabilities { .all }

    var noteFileURL: URL? { note.path }

    var noteWikiLinkConfig: WikiLinkConfig? {
        AppConfig.shared.config.notes.first { nc in
            if let info = note.periodicInfo {
                return nc.path == info.pathTemplate
            }
            return nc.resolvedPath == note.path.path
        }?.wikilink
    }

    func webViewContentChanged(_ text: String) {
        self.text = text
    }

    func webViewPastedImage(dataUrl: String, insertMarkdown: @escaping (String) -> Void) {
        handlePastedImage(dataUrl: dataUrl, completion: insertMarkdown)
    }

    func webViewFoldChanged(lines: [Int]) {
        updateFoldingState(lines: lines)
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
