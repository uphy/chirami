import AppKit

// MARK: - NotePanel

/// A floating NSPanel with minimal chrome for displaying a note.
class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private var closeButtonTrackingArea: NSTrackingArea?
    private var customTitleLabel: NSTextField?
    private var prevButton: NSButton?
    private var nextButton: NSButton?
    private var todayButton: NSButton?
    private var pinButton: NSButton?

    var onWarpKey: ((Character) -> Void)?
    var onHideRequest: (() -> Void)?

    override var title: String {
        didSet { customTitleLabel?.stringValue = title }
    }

    override func becomeKey() {
        super.becomeKey()
        // NSHostingView doesn't forward first responder to embedded NSTextViews.
        // Walk the view hierarchy to find and focus the text view.
        if let textView = contentView?.firstDescendant(of: MarkdownTextView.self) {
            makeFirstResponder(textView)
        }
    }

    /// Hide the system title and add a custom centered label in the titlebar.
    func centerTitle() {
        titleVisibility = .hidden

        guard let closeButton = standardWindowButton(.closeButton) else { return }

        // Walk up from the close button to find the full-width titlebar view
        var fullWidthView: NSView = closeButton
        while let parent = fullWidthView.superview {
            fullWidthView = parent
            if parent.frame.width >= frame.width - 1 { break }
        }

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

    /// Set up navigation buttons (◀ ▶ ●) in the titlebar for periodic notes.
    func setupNavigationButtons(
        target: AnyObject,
        prevAction: Selector,
        nextAction: Selector,
        todayAction: Selector
    ) {
        guard let closeButton = standardWindowButton(.closeButton) else { return }

        // Walk up to full-width titlebar view
        var fullWidthView: NSView = closeButton
        while let parent = fullWidthView.superview {
            fullWidthView = parent
            if parent.frame.width >= frame.width - 1 { break }
        }

        let prev = makeNavButton(symbolName: "chevron.left", action: prevAction, target: target)
        let next = makeNavButton(symbolName: "chevron.right", action: nextAction, target: target)
        let latest = makeNavButton(symbolName: "forward.end.fill", action: todayAction, target: target)
        latest.isHidden = true // hidden when showing latest

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

    /// Add a pin button to the right end of the titlebar (for auto_hide notes).
    func setupPinButton(target: AnyObject, action: Selector) {
        guard let closeButton = standardWindowButton(.closeButton) else { return }

        var fullWidthView: NSView = closeButton
        while let parent = fullWidthView.superview {
            fullWidthView = parent
            if parent.frame.width >= frame.width - 1 { break }
        }

        let button = makeNavButton(symbolName: "pin", action: action, target: target)
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
                NSCursor.closedHand.push()
                performDrag(with: event)
                NSCursor.pop()
                return
            }
            // Titlebar hover cursor
            let location = event.locationInWindow
            if location.y > contentLayoutRect.maxY && event.type == .mouseMoved {
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
            // ESC key (keyCode 53) with no modifiers hides the window
            if event.keyCode == 53 {
                let activeFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if activeFlags.isEmpty {
                    onHideRequest?()
                    return
                }
            }
            let warpFlags = AppConfig.shared.data.warpModifierFlags
            let activeFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad])
            if activeFlags == warpFlags {
                // hjkl keys
                if let char = event.charactersIgnoringModifiers?.first,
                   ["h", "j", "k", "l"].contains(char) {
                    onWarpKey?(char)
                    return
                }
                // Arrow keys mapped to hjkl equivalents
                let arrowKeyMap: [UInt16: Character] = [123: "h", 124: "l", 125: "j", 126: "k"]
                if let mapped = arrowKeyMap[event.keyCode] {
                    onWarpKey?(mapped)
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
