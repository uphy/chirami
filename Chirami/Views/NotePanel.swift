import AppKit
import WebKit
import os

// MARK: - NotePanel

/// A floating NSPanel with minimal chrome for displaying a note.
class NotePanel: NSPanel {
    /// Set to false during app startup to prevent stealKeyFocus at the WindowServer level.
    /// AppKit checks canBecomeKey before asking SkyLight to steal key focus, so this
    /// prevents focus from being taken from the previously active app on launch.
    static var startupMode = true

    override var canBecomeKey: Bool { !Self.startupMode }
    override var canBecomeMain: Bool { true }

    private var closeButtonTrackingArea: NSTrackingArea?
    private var customTitleLabel: NSTextField?
    private var prevButton: NSButton?
    private var nextButton: NSButton?
    private var todayButton: NSButton?
    private var pinButton: NSButton?
    private var didLogTitlebarHierarchy = false
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "NotePanel")

    var onHideRequest: (() -> Void)?
    var onTogglePin: (() -> Void)?

    private var pinAction: (() -> Void)?

    @objc private func pinButtonTapped() { pinAction?() }

    override var title: String {
        didSet { customTitleLabel?.stringValue = title }
    }

    override func becomeKey() {
        super.becomeKey()
        // NSHostingView doesn't forward first responder to embedded views automatically.
        // For WKWebView, makeFirstResponder alone doesn't focus the DOM content —
        // call focus() to also trigger JS focus() on the CodeMirror editor.
        if let noteWebView = contentView?.firstDescendant(of: NoteWebView.self) {
            noteWebView.focus()
        }
    }

    func applyConfiguredAppearance() {
        let appearance = configuredAppearance()
        self.appearance = appearance
        fullWidthTitlebarView()?.appearance = appearance
        customTitleLabel?.appearance = appearance
        [prevButton, nextButton, todayButton, pinButton].forEach { $0?.appearance = appearance }
        contentView?.superview?.appearance = appearance
        contentView?.needsDisplay = true
        invalidateShadow()
        displayIfNeeded()
    }

    /// Hide the system title and add a custom centered label in the titlebar.
    func centerTitle() {
        titleVisibility = .hidden

        guard let closeButton = standardWindowButton(.closeButton) else { return }
        logTitlebarHierarchyIfNeeded(closeButton: closeButton)

        guard let fullWidthView = fullWidthTitlebarView(startingAt: closeButton) else { return }

        let label = NSTextField(labelWithString: title)
        label.alignment = .center
        label.font = .titleBarFont(ofSize: NSFont.systemFontSize(for: .small))
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        fullWidthView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: fullWidthView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: fullWidthView.widthAnchor, constant: -60)
        ])

        customTitleLabel = label
    }

    /// Set up navigation buttons (◀ ▶ ●) in the titlebar for periodic/stream notes.
    /// - Parameter isStream: when true, the "jump to current" button is labeled
    ///   "Latest" instead of "Today" (stream-note-mode design: the Today button
    ///   becomes Latest for stream-mode notes).
    func setupNavigationButtons(
        target: AnyObject,
        prevAction: Selector,
        nextAction: Selector,
        todayAction: Selector,
        isStream: Bool = false
    ) {
        guard let closeButton = standardWindowButton(.closeButton) else { return }

        guard let fullWidthView = fullWidthTitlebarView(startingAt: closeButton) else { return }

        let prev = makeNavButton(symbolName: "chevron.left", action: prevAction, target: target)
        let next = makeNavButton(symbolName: "chevron.right", action: nextAction, target: target)
        let latest = makeNavButton(symbolName: "forward.end.fill", action: todayAction, target: target)
        latest.isHidden = true // hidden when showing latest
        latest.toolTip = isStream ? "Latest" : "Today"

        for button in [prev, next, latest] {
            fullWidthView.addSubview(button)
            button.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor).isActive = true
        }

        if let label = customTitleLabel {
            prev.trailingAnchor.constraint(equalTo: label.leadingAnchor, constant: -4).isActive = true
            next.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4).isActive = true
            latest.leadingAnchor.constraint(equalTo: next.trailingAnchor, constant: 2).isActive = true
        }

        prevButton = prev
        nextButton = next
        todayButton = latest
    }

    /// Update navigation button enabled/hidden states.
    func updateNavigationState(hasPrevious: Bool, hasNext: Bool, isToday: Bool) {
        prevButton?.isEnabled = hasPrevious
        nextButton?.isEnabled = hasNext
        todayButton?.isHidden = isToday
    }

    /// Add a pin button to the right end of the titlebar.
    func setupPinButton(onToggle: @escaping () -> Void) {
        pinAction = onToggle
        onTogglePin = onToggle

        guard let closeButton = standardWindowButton(.closeButton) else { return }
        guard let fullWidthView = fullWidthTitlebarView(startingAt: closeButton) else { return }

        let button = makeNavButton(symbolName: "pin", action: #selector(pinButtonTapped), target: self)
        fullWidthView.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            button.trailingAnchor.constraint(equalTo: fullWidthView.trailingAnchor, constant: -8)
        ])

        pinButton = button
    }

    /// Update the pin button icon and color to reflect pinned state.
    func updatePinState(isPinned: Bool) {
        pinButton?.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        pinButton?.contentTintColor = isPinned ? .labelColor : .secondaryLabelColor
    }

    private func makeNavButton(symbolName: String, action: Selector, target: AnyObject) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.action = action
        button.target = target
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.controlSize = .small
        return button
    }

    private func configuredAppearance() -> NSAppearance? {
        switch AppConfig.shared.config.appearance?.mode ?? .auto {
        case .auto:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    private func fullWidthTitlebarView() -> NSView? {
        guard let closeButton = standardWindowButton(.closeButton) else { return nil }
        return fullWidthTitlebarView(startingAt: closeButton)
    }

    private func fullWidthTitlebarView(startingAt view: NSView) -> NSView? {
        var fullWidthView: NSView = view
        while let parent = fullWidthView.superview {
            fullWidthView = parent
            if parent.frame.width >= frame.width - 1 { break }
        }
        return fullWidthView
    }

    private func logTitlebarHierarchyIfNeeded(closeButton: NSButton) {
        guard !didLogTitlebarHierarchy else { return }
        guard ProcessInfo.processInfo.environment["CHIRAMI_DEBUG_TITLEBAR"] == "1" else { return }
        didLogTitlebarHierarchy = true

        logger.debug("[Titlebar] window=\(self.title, privacy: .public) frame=\(String(describing: self.frame), privacy: .public)")
        var current: NSView? = closeButton
        var level = 0
        while let view = current {
            let layerColor = view.layer?.backgroundColor.map { NSColor(cgColor: $0)?.description ?? "cgColor" } ?? "nil"
            logger.debug(
                """
                [Titlebar] level=\(level) type=\(String(describing: type(of: view)), privacy: .public) \
                frame=\(String(describing: view.frame), privacy: .public) \
                wantsLayer=\(view.wantsLayer) layerBg=\(layerColor, privacy: .public)
                """
            )
            current = view.superview
            level += 1
        }
        if let contentView {
            logger.debug("[Titlebar] contentView type=\(String(describing: type(of: contentView)), privacy: .public) frame=\(String(describing: contentView.frame), privacy: .public)")
            if let superview = contentView.superview {
                logger.debug("[Titlebar] contentSuperview type=\(String(describing: type(of: superview)), privacy: .public) frame=\(String(describing: superview.frame), privacy: .public)")
            }
        }
    }

    /// Hide the close button by default and show it on titlebar hover.
    func setupCloseButtonHover() {
        guard let closeButton = standardWindowButton(.closeButton),
              let titlebarView = closeButton.superview else { return }

        closeButton.alphaValue = 0

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        titlebarView.addTrackingArea(trackingArea)
        closeButtonTrackingArea = trackingArea
    }

    override func performClose(_ sender: Any?) {
        onHideRequest?()
    }

    override func sendEvent(_ event: NSEvent) {
        let dragFlags = AppConfig.shared.data.dragModifierFlags
        if event.modifierFlags.contains(dragFlags) {
            // Handle modifier+drag for the entire window (not just titlebar)
            if event.type == .leftMouseDown {
                let initialMouseLocation = NSEvent.mouseLocation
                let initialOrigin = frame.origin
                NSCursor.closedHand.push()
                disableCursorRects()

                while true {
                    guard let next = nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { break }
                    if next.type == .leftMouseUp { break }
                    let current = NSEvent.mouseLocation
                    setFrameOrigin(CGPoint(
                        x: initialOrigin.x + (current.x - initialMouseLocation.x),
                        y: initialOrigin.y + (current.y - initialMouseLocation.y)
                    ))
                }

                enableCursorRects()
                NSCursor.pop()
                return
            }
            // Show openHand cursor anywhere in the window while drag modifier is held
            if event.type == .mouseMoved {
                super.sendEvent(event)
                NSCursor.openHand.set()
                return
            }
        }
        if event.type == .keyDown {
            // Command+W (keyCode 13) hides the window
            if event.keyCode == 13,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
                onHideRequest?()
                return
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .option],
               event.charactersIgnoringModifiers == "p" {
                onTogglePin?()
                return
            }
            // ESC key (keyCode 53) with no modifiers hides the window, unless a
            // WebView overlay (Excalidraw) or the CodeMirror search panel is open —
            // dispatch ESC to JS instead so it closes the overlay/panel first.
            // NOTE: do NOT call super.sendEvent for ESC; it triggers cancelOperation:/
            // performClose: which closes the panel regardless of onHideRequest.
            if event.keyCode == 53 {
                let activeFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if activeFlags.isEmpty {
                    if let webView = contentView?.firstDescendant(of: NoteWebView.self),
                       webView.overlayVisible || webView.searchPanelVisible {
                        webView.dispatchEscapeKey()
                    } else {
                        onHideRequest?()
                    }
                    return
                }
            }
        }
        super.sendEvent(event)
    }

    override func mouseEntered(with event: NSEvent) {
        guard let closeButton = standardWindowButton(.closeButton) else {
            super.mouseEntered(with: event)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard let closeButton = standardWindowButton(.closeButton) else {
            super.mouseExited(with: event)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = 0
        }
    }
}

extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let found = subview.firstDescendant(of: type) { return found }
        }
        return nil
    }
}
