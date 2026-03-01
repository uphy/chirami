import AppKit

// MARK: - DisplayWindowController

/// Manages a single Ad-hoc Note window opened via chirami://display URI.
@MainActor
class DisplayWindowController: NSObject, NSWindowDelegate {

    let panel: DisplayPanel
    let profileName: String?
    let windowId: String?
    private let position: NotePosition
    private let transparency: Double
    private(set) var isPinned: Bool
    /// When true, closing this window should NOT notify FIFO (used during --id replacement).
    var suppressCloseNotification = false

    init(panel: DisplayPanel, profileName: String? = nil, windowId: String? = nil, position: NotePosition = .fixed, transparency: Double = 0.9, isPinned: Bool = true) {
        self.panel = panel
        self.profileName = profileName
        self.windowId = windowId
        self.position = position
        self.transparency = transparency
        self.isPinned = isPinned
        super.init()
        panel.delegate = self

        if position == .cursor {
            panel.setupPinButton(target: self, action: #selector(togglePinAction))
            panel.updatePinState(isPinned: isPinned)
        }
    }

    /// Place the panel and show it.
    func show(at origin: CGPoint? = nil) {
        if let origin {
            panel.setFrameOrigin(origin)
        } else if position == .cursor {
            showAtCursor()
            return
        } else {
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowSize = panel.frame.size
                let x = screenFrame.midX - windowSize.width / 2
                let y = screenFrame.midY - windowSize.height / 2
                panel.setFrameOrigin(CGPoint(x: x, y: y))
            }
        }
        panel.orderFront(nil)
    }

    private func showAtCursor() {
        let cursorLocation = NSEvent.mouseLocation
        let windowSize = panel.frame.size
        let screen = screenForCursor() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        var origin = CGPoint(x: cursorLocation.x - windowSize.width / 2, y: cursorLocation.y - windowSize.height / 2)
        origin = clampToScreen(origin: origin, windowSize: windowSize, visibleFrame: visibleFrame)
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
    }

    private func screenForCursor() -> NSScreen? {
        let cursorLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens where NSMouseInRect(cursorLocation, screen.frame, false) {
            return screen
        }
        return NSScreen.main
    }

    private func clampToScreen(origin: CGPoint, windowSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        var x = origin.x
        var y = origin.y
        if x + windowSize.width > visibleFrame.maxX { x = visibleFrame.maxX - windowSize.width }
        if x < visibleFrame.minX { x = visibleFrame.minX }
        if y < visibleFrame.minY { y = visibleFrame.minY }
        if y + windowSize.height > visibleFrame.maxY { y = visibleFrame.maxY - windowSize.height }
        return CGPoint(x: x, y: y)
    }

    func setVisible(_ visible: Bool) {
        if visible {
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = transparency
            }
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.panel.orderOut(nil)
                    self?.panel.alphaValue = self?.transparency ?? 0.9
                }
            })
        }
    }

    @objc func togglePinAction() {
        isPinned.toggle()
        panel.updatePinState(isPinned: isPinned)
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard !isPinned, panel.isVisible else { return }
        setVisible(false)
    }

    func windowWillClose(_ notification: Notification) {
        if suppressCloseNotification {
            panel.didNotifyClosed = true  // prevent FIFO write
        }
        DisplayWindowManager.shared.removeController(self)
    }

    func windowDidMove(_ notification: Notification) {
        saveStateIfNeeded()
    }

    func windowDidResize(_ notification: Notification) {
        saveStateIfNeeded()
    }

    private func saveStateIfNeeded() {
        guard let windowId else { return }
        let stateKey = "adhoc:\(windowId)"
        AppState.shared.update { state in
            var ws = state.windows[stateKey] ?? WindowState(
                position: self.panel.frame.origin,
                size: self.panel.frame.size,
                visible: true
            )
            ws.position = [self.panel.frame.origin.x, self.panel.frame.origin.y]
            ws.size = [self.panel.frame.size.width, self.panel.frame.size.height]
            ws.lastUsed = Date()
            state.windows[stateKey] = ws
        }
    }
}

// MARK: - DisplayWindowManager

/// Manages all Ad-hoc Note windows opened via chirami://display URIs.
/// Parses URL parameters and creates/destroys DisplayWindowController instances.
@MainActor
class DisplayWindowManager {

    static let shared = DisplayWindowManager()

    /// Anonymous (id-less) Ad-hoc Note windows.
    private var controllers: [ObjectIdentifier: DisplayWindowController] = [:]
    /// Named (--id) Ad-hoc Note windows, keyed by id.
    private var namedControllers: [String: DisplayWindowController] = [:]

    private init() {}

    /// All managed controllers (both named and anonymous).
    var allControllers: [DisplayWindowController] {
        Array(controllers.values) + Array(namedControllers.values)
    }

    /// Parse a chirami://display URL and open a floating window.
    func display(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let queryItems = components.queryItems ?? []

        func param(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        let filePath = param("file")
        let content = param("content")
        let isReadOnly = param("readonly") == "1"
        let callbackPipePath = param("callback_pipe")
        let profileName = param("profile")
        let windowId = param("id")

        // Resolve profile settings
        let profile = profileName.flatMap { AppConfig.shared.config.adhoc?.profiles?[$0] }
        let color = profile?.resolveColor() ?? .yellow
        let transparency = profile?.resolveTransparency() ?? 0.9
        let fontSize = profile?.resolveFontSize() ?? 14
        let position = profile?.resolvePosition() ?? .fixed
        let customTitle = profile?.title

        // Validate callback_pipe: only allow paths under /tmp/ or $TMPDIR
        let validPipe: String? = callbackPipePath.flatMap { isValidCallbackPipe($0) ? $0 : nil }

        // Determine display content and file URL
        let displayContent: String
        let fileURL: URL?
        let readOnly: Bool

        if let filePath = filePath {
            let fileURLCandidate = URL(fileURLWithPath: filePath)
            if isReadOnly {
                displayContent = (try? String(contentsOf: fileURLCandidate, encoding: .utf8)) ?? ""
                fileURL = nil
            } else {
                displayContent = (try? String(contentsOf: fileURLCandidate, encoding: .utf8)) ?? ""
                fileURL = fileURLCandidate
            }
            readOnly = isReadOnly
        } else if let content = content {
            displayContent = content
            fileURL = nil
            readOnly = true
        } else {
            return // No content provided
        }

        // Handle --id replacement: close existing window with same id, inherit position/size
        var inheritedFrame: NSRect?
        if let windowId, let existing = namedControllers[windowId] {
            inheritedFrame = existing.panel.frame
            existing.suppressCloseNotification = true
            existing.panel.close()
        }

        let isPinned = position != .cursor
        let panel = DisplayPanel(callbackPipePath: validPipe, isReadOnly: readOnly, color: color, transparency: transparency, customTitle: customTitle)
        panel.centerTitle()
        panel.setupCloseButtonHover()
        let contentView = DisplayContentView(content: displayContent, fileURL: fileURL, isReadOnly: readOnly, noteColor: color, fontSize: fontSize)
        panel.contentView = contentView

        let controller = DisplayWindowController(
            panel: panel,
            profileName: profileName,
            windowId: windowId,
            position: position,
            transparency: transparency,
            isPinned: isPinned
        )

        // Determine window origin
        var origin: CGPoint?

        if let inheritedFrame {
            // --id replacement: reuse previous position/size
            panel.setFrame(inheritedFrame, display: false)
            origin = inheritedFrame.origin
        } else if let windowId {
            // Restore saved state for --id windows
            let stateKey = "adhoc:\(windowId)"
            if let savedState = AppState.shared.windowState(for: stateKey) {
                panel.setFrame(NSRect(origin: savedState.cgPoint, size: savedState.cgSize), display: false)
                origin = savedState.cgPoint
                // Update lastUsed
                AppState.shared.update { state in
                    state.windows[stateKey]?.lastUsed = Date()
                }
            }
        }

        // Apply overlap prevention
        origin = avoidOverlap(origin: origin, windowSize: panel.frame.size, profileName: profileName, position: position)

        if let windowId {
            namedControllers[windowId] = controller
        } else {
            controllers[ObjectIdentifier(controller)] = controller
        }
        controller.show(at: origin)
    }

    func removeController(_ controller: DisplayWindowController) {
        if let windowId = controller.windowId {
            namedControllers.removeValue(forKey: windowId)
        } else {
            controllers.removeValue(forKey: ObjectIdentifier(controller))
        }
    }

    /// Toggle visibility of all Ad-hoc Notes belonging to a profile.
    func toggleProfile(_ profileName: String) {
        let matching = allControllers.filter { $0.profileName == profileName }
        guard !matching.isEmpty else { return }

        let anyVisible = matching.contains { $0.panel.isVisible && $0.panel.alphaValue > 0 }
        for controller in matching {
            controller.setVisible(!anyVisible)
        }
    }

    // MARK: - Overlap Prevention

    /// Adjust origin to avoid overlapping with visible windows of the same profile.
    private func avoidOverlap(origin: CGPoint?, windowSize: CGSize, profileName: String?, position: NotePosition) -> CGPoint? {
        guard let candidate = origin else { return nil }

        let sameProfileControllers = allControllers.filter {
            $0.profileName == profileName && $0.panel.isVisible
        }

        var adjusted = candidate
        let offset: CGFloat = 20
        var maxAttempts = 50

        while maxAttempts > 0 {
            let overlaps = sameProfileControllers.contains { controller in
                abs(controller.panel.frame.origin.x - adjusted.x) < 1 &&
                abs(controller.panel.frame.origin.y - adjusted.y) < 1
            }
            if !overlaps { break }
            adjusted.x += offset
            adjusted.y += offset
            maxAttempts -= 1
        }

        return adjusted
    }

    // MARK: - Validation

    /// Allow callback_pipe paths only under /tmp/ or $TMPDIR.
    private func isValidCallbackPipe(_ path: String) -> Bool {
        let tmpDir = NSTemporaryDirectory()
        return path.hasPrefix("/tmp/") || path.hasPrefix(tmpDir)
    }
}
