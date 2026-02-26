import AppKit

/// NSTextView subclass that intercepts clicks on task checkboxes and handles list editing.
class MarkdownTextView: NSTextView {
    var onCheckboxClick: ((Int) -> Void)?
    var onFontSizeChange: ((CGFloat) -> Void)?
    var customMenuItems: (() -> [NSMenuItem])?
    var currentFontSize: CGFloat = 14
    private var isDragModifierHeld = false
    var isAdjustingCursorForHiddenPrefix = false
    var noteURL: URL?
    var attachmentsDir: URL?

    private var dragModifierFlags: NSEvent.ModifierFlags {
        AppConfig.shared.data.dragModifierFlags
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if let items = customMenuItems?(), !items.isEmpty {
            menu.addItem(.separator())
            for item in items {
                menu.addItem(item)
            }
        }
        return menu
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        if event.modifierFlags.contains(dragModifierFlags) {
            NSCursor.openHand.set()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if charIndexOfCheckbox(at: point) != nil || linkURL(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if event.modifierFlags.contains(dragModifierFlags) {
            if !isDragModifierHeld {
                isDragModifierHeld = true
                NSCursor.openHand.push()
            }
        } else {
            if isDragModifierHeld {
                isDragModifierHeld = false
                NSCursor.pop()
            }
        }
        super.flagsChanged(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        // Modifier+drag: initiate window move instead of text interaction
        if event.modifierFlags.contains(dragModifierFlags) {
            // Reset cursor stack: pop openHand if held, push closedHand
            if isDragModifierHeld {
                NSCursor.pop()
            }
            NSCursor.closedHand.push()
            window?.performDrag(with: event)
            // performDrag returns after drag completes; re-evaluate modifier state
            NSCursor.pop()
            let modifierStillHeld = NSEvent.modifierFlags.contains(dragModifierFlags)
            if modifierStillHeld {
                NSCursor.openHand.push()
                isDragModifierHeld = true
            } else {
                isDragModifierHeld = false
            }
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        if let idx = charIndexOfCheckbox(at: point) {
            onCheckboxClick?(idx)
            return
        }
        if let url = linkURL(at: point) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    private func linkURL(at point: NSPoint) -> URL? {
        guard let storage = textStorage else { return nil }
        let charIndex = characterIndexForInsertion(at: point)
        guard charIndex < storage.length else { return nil }
        return storage.attribute(.link, at: charIndex, effectiveRange: nil) as? URL
    }

    private func charIndexOfCheckbox(at point: NSPoint) -> Int? {
        guard let storage = textStorage else { return nil }
        let charIndex = characterIndexForInsertion(at: point)
        if charIndex < storage.length,
           storage.attribute(.taskCheckbox, at: charIndex, effectiveRange: nil) != nil {
            return charIndex
        }
        if charIndex > 0,
           storage.attribute(.taskCheckbox, at: charIndex - 1, effectiveRange: nil) != nil {
            return charIndex - 1
        }

        // Fallback for nested items: the hidden leading chars (whitespace + marker) have
        // near-zero width, so characterIndexForInsertion misses them. Use a line-based
        // hit test comparing against the visual checkbox position drawn by BulletLayoutManager.
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let containerOrigin = textContainerOrigin
        let ptInContainer = NSPoint(x: point.x - containerOrigin.x, y: point.y - containerOrigin.y)

        var lineGlyphRange = NSRange()
        let glyphIndex = lm.glyphIndex(for: ptInContainer, in: tc, fractionOfDistanceThroughGlyph: nil)
        let lineFragRect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
        let lineCharRange = lm.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)

        var foundIndex: Int?
        storage.enumerateAttribute(.taskCheckbox, in: lineCharRange, options: []) { value, range, stop in
            guard value != nil else { return }
            let level = storage.attribute(.listNestingLevel, at: range.location, effectiveRange: nil) as? Int ?? 0
            let checkboxX = containerOrigin.x + lineFragRect.origin.x + 2 + CGFloat(level) * 20
            let checkboxWidth = self.currentFontSize * 1.2
            if point.x >= checkboxX && point.x <= checkboxX + checkboxWidth {
                foundIndex = range.location
                stop.pointee = true
            }
        }
        return foundIndex
    }

    // MARK: - Surround selection with paired characters

    private static let surroundPairs: [String: (String, String)] = [
        "*": ("*", "*"),
        "_": ("_", "_"),
        "`": ("`", "`"),
        "~": ("~", "~"),
        "(": ("(", ")"),
        "[": ("[", "]"),
        "{": ("{", "}"),
        "\"": ("\"", "\""),
        "'": ("'", "'")
    ]

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let typed: String
        if let s = string as? String {
            typed = s
        } else if let s = string as? NSAttributedString {
            typed = s.string
        } else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        let sel = selectedRange()
        if sel.length > 0, let pair = Self.surroundPairs[typed] {
            let storage = textStorage!
            let selectedText = (storage.string as NSString).substring(with: sel)
            let replacement = "\(pair.0)\(selectedText)\(pair.1)"
            if shouldChangeText(in: sel, replacementString: replacement) {
                storage.replaceCharacters(in: sel, with: replacement)
                // Select the inner text (excluding the wrapping characters)
                let innerStart = sel.location + (pair.0 as NSString).length
                let innerLength = (selectedText as NSString).length
                setSelectedRange(NSRange(location: innerStart, length: innerLength))
                didChangeText()
            }
            return
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: - Current line helper

    struct CurrentLine {
        let storage: NSTextStorage
        let nsString: NSString
        let cursorLocation: Int
        let lineRange: NSRange
        let trimmedLine: String
        let fullRange: NSRange
    }

    func currentLine() -> CurrentLine? {
        guard let storage = textStorage else { return nil }
        let nsString = storage.string as NSString
        let cursorLocation = selectedRange().location
        let lineRange = nsString.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let lineText = nsString.substring(with: lineRange)
        let trimmedLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
        let fullRange = NSRange(location: 0, length: (trimmedLine as NSString).length)
        return CurrentLine(storage: storage, nsString: nsString, cursorLocation: cursorLocation, lineRange: lineRange, trimmedLine: trimmedLine, fullRange: fullRange)
    }

    // swiftlint:disable force_try
    /// Matches the hidden prefix of a task list line: optional indent + marker + " [ ] " or " [x] "
    private static let taskLinePrefixPattern = try! NSRegularExpression(
        pattern: #"^[ \t]*[-*] \[[ xX]\] "#
    )
    /// Matches the prefix of a regular list line: optional indent + marker + space
    private static let listPrefixPattern = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:[-*+]|\d+[.)]) "#
    )
    // swiftlint:enable force_try

    /// Returns both the line start and the content start of a list line containing `location`.
    /// For task lines, only matches when in rendered/hidden mode (`.taskCheckbox` attribute present).
    /// For regular list lines (`- `, `* `, `1. `, etc.), always matches.
    /// Returns nil for non-list lines.
    private func lineAndContentStart(at location: Int) -> (lineStart: Int, contentStart: Int)? {
        guard let storage = textStorage else { return nil }
        let nsString = storage.string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
        let lineText = nsString.substring(with: lineRange)
        let lineNS = lineText as NSString
        let fullRange = NSRange(location: 0, length: lineNS.length)

        // 1) Task line with rendered checkbox (existing behavior)
        var hasRenderedCheckbox = false
        storage.enumerateAttribute(.taskCheckbox, in: lineRange, options: []) { value, _, stop in
            if value != nil { hasRenderedCheckbox = true; stop.pointee = true }
        }
        if hasRenderedCheckbox,
           let match = Self.taskLinePrefixPattern.firstMatch(in: lineText, range: fullRange) {
            return (lineStart: lineRange.location,
                    contentStart: lineRange.location + NSMaxRange(match.range))
        }

        // 2) Regular list line (prefix always visible in raw mode)
        if let match = Self.listPrefixPattern.firstMatch(in: lineText, range: fullRange) {
            return (lineStart: lineRange.location,
                    contentStart: lineRange.location + NSMaxRange(match.range))
        }

        return nil
    }

    // MARK: - Cursor movement: skip hidden line prefixes

    override func moveToBeginningOfParagraph(_ sender: Any?) {
        guard let result = lineAndContentStart(at: selectedRange().location) else {
            super.moveToBeginningOfParagraph(sender)
            return
        }
        if selectedRange().location == result.contentStart {
            // Toggle to lineStart; let applyStyling switch to raw mode
            setSelectedRange(NSRange(location: result.lineStart, length: 0))
        } else {
            isAdjustingCursorForHiddenPrefix = true
            defer { isAdjustingCursorForHiddenPrefix = false }
            setSelectedRange(NSRange(location: result.contentStart, length: 0))
        }
    }

    override func moveToBeginningOfLine(_ sender: Any?) {
        guard let result = lineAndContentStart(at: selectedRange().location) else {
            super.moveToBeginningOfLine(sender)
            return
        }
        if selectedRange().location == result.contentStart {
            // Toggle to lineStart; let applyStyling switch to raw mode
            setSelectedRange(NSRange(location: result.lineStart, length: 0))
        } else {
            isAdjustingCursorForHiddenPrefix = true
            defer { isAdjustingCursorForHiddenPrefix = false }
            setSelectedRange(NSRange(location: result.contentStart, length: 0))
        }
    }

    override func moveToBeginningOfParagraphAndModifySelection(_ sender: Any?) {
        guard let result = lineAndContentStart(at: selectedRange().location) else {
            super.moveToBeginningOfParagraphAndModifySelection(sender)
            return
        }
        let sel = selectedRange()
        let anchor = sel.location + sel.length
        if sel.location == result.contentStart {
            // Toggle to lineStart; let applyStyling switch to raw mode
            setSelectedRange(NSRange(location: result.lineStart, length: anchor - result.lineStart))
        } else {
            isAdjustingCursorForHiddenPrefix = true
            defer { isAdjustingCursorForHiddenPrefix = false }
            setSelectedRange(NSRange(location: result.contentStart, length: anchor - result.contentStart))
        }
    }

    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        guard let result = lineAndContentStart(at: selectedRange().location) else {
            super.moveToBeginningOfLineAndModifySelection(sender)
            return
        }
        let sel = selectedRange()
        let anchor = sel.location + sel.length
        if sel.location == result.contentStart {
            // Toggle to lineStart; let applyStyling switch to raw mode
            setSelectedRange(NSRange(location: result.lineStart, length: anchor - result.lineStart))
        } else {
            isAdjustingCursorForHiddenPrefix = true
            defer { isAdjustingCursorForHiddenPrefix = false }
            setSelectedRange(NSRange(location: result.contentStart, length: anchor - result.contentStart))
        }
    }

    // MARK: - Copy/Cut: include hidden prefixes

    /// Returns the line-start index if all characters from line start up to `location`
    /// are hidden (font size < 1.0). Returns nil otherwise (e.g. raw-edit mode).
    private func lineStartIncludingHiddenPrefix(at location: Int) -> Int? {
        guard let storage = textStorage else { return nil }
        let nsString = storage.string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
        guard location > lineRange.location else { return nil }

        let prefixRange = NSRange(location: lineRange.location, length: location - lineRange.location)
        var allHidden = true
        storage.enumerateAttribute(.foregroundColor, in: prefixRange, options: []) { value, _, stop in
            guard let color = value as? NSColor else {
                allHidden = false
                stop.pointee = true
                return
            }
            if color.alphaComponent > 0 {
                allHidden = false
                stop.pointee = true
            }
        }
        return allHidden ? lineRange.location : nil
    }

    override func copy(_ sender: Any?) {
        guard let storage = textStorage else { super.copy(sender); return }
        let sel = selectedRange()
        guard sel.length > 0 else { super.copy(sender); return }

        let nsString = storage.string as NSString
        let start = lineStartIncludingHiddenPrefix(at: sel.location) ?? sel.location
        let expandedRange = NSRange(location: start, length: sel.length + (sel.location - start))
        let text = nsString.substring(with: expandedRange)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    override func cut(_ sender: Any?) {
        guard let storage = textStorage else { super.cut(sender); return }
        let sel = selectedRange()
        guard sel.length > 0 else { super.cut(sender); return }

        let nsString = storage.string as NSString
        let start = lineStartIncludingHiddenPrefix(at: sel.location) ?? sel.location
        let expandedRange = NSRange(location: start, length: sel.length + (sel.location - start))
        let text = nsString.substring(with: expandedRange)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        if shouldChangeText(in: sel, replacementString: "") {
            storage.replaceCharacters(in: sel, with: "")
            setSelectedRange(NSRange(location: sel.location, length: 0))
            didChangeText()
        }
    }

    // MARK: - Font size adjustment

    private func adjustFontSize(by delta: CGFloat) {
        let newSize = delta > 0 ? min(currentFontSize + delta, 32) : max(currentFontSize + delta, 8)
        if newSize != currentFontSize {
            currentFontSize = newSize
            onFontSizeChange?(newSize)
        }
    }

    // MARK: - Image paste

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        guard let types = pb.types else {
            super.paste(sender)
            return
        }

        let hasImage = types.contains(.tiff) || types.contains(.png)
        let textContent = pb.string(forType: .string)
        let hasText = textContent.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false

        NSLog("[Chirami] paste: types=\(types.map(\.rawValue)), hasImage=\(hasImage), hasText=\(hasText), noteURL=\(String(describing: noteURL)), attachmentsDir=\(String(describing: attachmentsDir))")

        // If there's meaningful text content, prefer text paste (existing behavior)
        if hasText {
            super.paste(sender)
            return
        }

        guard hasImage,
              let noteURL = noteURL,
              let attachmentsDir = attachmentsDir else {
            super.paste(sender)
            return
        }

        // Extract image from pasteboard
        guard let image = NSImage(pasteboard: pb) else {
            NSLog("[Chirami] paste: failed to create NSImage from pasteboard")
            super.paste(sender)
            return
        }

        let service = ImagePasteService()
        switch service.save(image: image, to: attachmentsDir, noteURL: noteURL) {
        case .success(let result):
            NSLog("[Chirami] paste: image saved to \(result.fileURL.path)")
            insertSmartPasteText(result.markdownText)
        case .failure(let error):
            NSLog("[Chirami] paste: image save failed: \(error)")
            super.paste(sender)
        }
    }

    // MARK: - Keyboard shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+Shift+V: Smart Paste
        if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "v" {
            let config = AppConfig.shared.data.smartPaste
            if config?.enabled != false {
                performSmartPaste()
                return true
            }
            // disabled → fall through to default paste
        }

        if flags == .command, let chars = event.charactersIgnoringModifiers {
            switch chars {
            case "v":
                paste(nil)
                return true
            case "l":
                toggleTaskList()
                return true
            case "=", "+":
                adjustFontSize(by: 1)
                return true
            case "-":
                adjustFontSize(by: -1)
                return true
            case "b":
                wrapWithMarkdown(open: "**", close: "**")
                return true
            case "i":
                wrapWithMarkdown(open: "*", close: "*")
                return true
            case "f":
                // LSUIElement apps have no menu bar, so NSTextView's find bar won't
                // be triggered automatically. Invoke it directly.
                let item = NSMenuItem()
                item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
                performFindPanelAction(item)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Smart Paste

    private func performSmartPaste() {
        let service = SmartPasteService.shared
        guard let contentType = service.detectContentType() else { return }

        let config = AppConfig.shared.data.smartPaste
        let fetchUrlTitle = config?.fetchUrlTitle != false
        let result = service.convert(contentType, fetchUrlTitle: fetchUrlTitle)

        insertSmartPasteText(result.markdown)

        if let url = result.pendingTitleFetch {
            // Track the placeholder range for async title update.
            // The placeholder is "[](URL)" and we need to replace the empty "" between [ and ].
            let placeholderLink = "[](\(url.absoluteString))"
            let storage = textStorage!
            let fullText = storage.string as NSString

            // Find the placeholder we just inserted, searching backwards from cursor.
            let cursorPos = selectedRange().location
            let searchRange = NSRange(location: max(0, cursorPos - (placeholderLink as NSString).length - 1),
                                      length: min((placeholderLink as NSString).length + 1, cursorPos))
            let placeholderRange = fullText.range(of: placeholderLink, options: .backwards, range: searchRange)

            guard placeholderRange.location != NSNotFound else { return }

            Task {
                let title = await service.fetchTitle(for: url)
                let linkText = title ?? url.absoluteString
                // Re-find the placeholder in case text shifted
                let currentText = storage.string as NSString
                let currentPlaceholder = "[](\(url.absoluteString))"
                let currentRange = currentText.range(of: currentPlaceholder)
                guard currentRange.location != NSNotFound else { return }

                let insertLoc = currentRange.location + 1
                let insertRange = NSRange(location: insertLoc, length: 0)
                if self.shouldChangeText(in: insertRange, replacementString: linkText) {
                    storage.replaceCharacters(in: insertRange, with: linkText)
                    self.didChangeText()
                }
            }
        }
    }

    private func insertSmartPasteText(_ text: String) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        if shouldChangeText(in: sel, replacementString: text) {
            storage.replaceCharacters(in: sel, with: text)
            let newCursor = sel.location + (text as NSString).length
            setSelectedRange(NSRange(location: newCursor, length: 0))
            didChangeText()
        }
    }

    override func doCommand(by aSelector: Selector) {
        // In LSUIElement apps without a menu bar, undo:/redo: walk the responder
        // chain but find no handler, resulting in NSBeep(). Dispatch directly.
        if aSelector == #selector(UndoManager.undo) {
            undoManager?.undo()
            return
        }
        if aSelector == #selector(UndoManager.redo) {
            undoManager?.redo()
            return
        }
        // For commands this text view can handle (setMark:, insertNewline:, etc.),
        // delegate to the normal NSTextView dispatch.
        // For unknown commands, silently ignore instead of beeping.
        if responds(to: aSelector) {
            super.doCommand(by: aSelector)
        }
    }

    // MARK: - Inline Markdown wrapping (bold / italic)

    private func wrapWithMarkdown(open: String, close: String) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        let nsString = storage.string as NSString
        let fullLength = nsString.length
        let openLen = (open as NSString).length
        let closeLen = (close as NSString).length

        if sel.length > 0 {
            // If the selection is already surrounded by these markers, unwrap it.
            let beforeStart = sel.location - openLen
            let afterEnd = sel.location + sel.length + closeLen
            if beforeStart >= 0 && afterEnd <= fullLength {
                let beforeRange = NSRange(location: beforeStart, length: openLen)
                let afterRange = NSRange(location: sel.location + sel.length, length: closeLen)
                if nsString.substring(with: beforeRange) == open &&
                    nsString.substring(with: afterRange) == close {
                    let fullRange = NSRange(location: beforeStart, length: openLen + sel.length + closeLen)
                    let inner = nsString.substring(with: sel)
                    if shouldChangeText(in: fullRange, replacementString: inner) {
                        storage.replaceCharacters(in: fullRange, with: inner)
                        setSelectedRange(NSRange(location: beforeStart, length: (inner as NSString).length))
                        didChangeText()
                    }
                    return
                }
            }
            // Wrap the selection.
            let inner = nsString.substring(with: sel)
            let wrapped = "\(open)\(inner)\(close)"
            if shouldChangeText(in: sel, replacementString: wrapped) {
                storage.replaceCharacters(in: sel, with: wrapped)
                setSelectedRange(NSRange(location: sel.location + openLen, length: (inner as NSString).length))
                didChangeText()
            }
        } else {
            // No selection: insert the marker pair and place the cursor between them.
            let insertion = "\(open)\(close)"
            let insertRange = NSRange(location: sel.location, length: 0)
            if shouldChangeText(in: insertRange, replacementString: insertion) {
                storage.replaceCharacters(in: insertRange, with: insertion)
                setSelectedRange(NSRange(location: sel.location + openLen, length: 0))
                didChangeText()
            }
        }
    }
}
