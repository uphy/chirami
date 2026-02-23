import AppKit

/// NSTextView subclass that intercepts clicks on task checkboxes and handles list editing.
class MarkdownTextView: NSTextView {
    var onCheckboxClick: ((Int) -> Void)?
    var onFontSizeChange: ((CGFloat) -> Void)?
    var customMenuItems: (() -> [NSMenuItem])?
    var currentFontSize: CGFloat = 14

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
        let point = convert(event.locationInWindow, from: nil)
        if charIndexOfCheckbox(at: point) != nil || linkURL(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
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

    func isListItem(_ line: String, range: NSRange) -> Bool {
        Self.unorderedListPattern.firstMatch(in: line, range: range) != nil
            || Self.orderedListPattern.firstMatch(in: line, range: range) != nil
    }

    // MARK: - Font size adjustment

    private func adjustFontSize(by delta: CGFloat) {
        let newSize = delta > 0 ? min(currentFontSize + delta, 32) : max(currentFontSize + delta, 8)
        if newSize != currentFontSize {
            currentFontSize = newSize
            onFontSizeChange?(newSize)
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

    // swiftlint:disable force_try
    private static let taskCheckedPattern = try! NSRegularExpression(
        pattern: #"^(\s*)([-*])\s\[[xX]\]\s(.*)$"#
    )
    private static let taskUncheckedPattern = try! NSRegularExpression(
        pattern: #"^(\s*)([-*])\s\[ \]\s(.*)$"#
    )
    private static let listItemPattern = try! NSRegularExpression(
        pattern: #"^(\s*)([-*])\s(.*)$"#
    )
    private static let plainLinePattern = try! NSRegularExpression(
        pattern: #"^(\s*)(.+)$"#
    )
    // swiftlint:enable force_try

    private func toggleTaskList() {
        guard let cl = currentLine() else { return }
        let storage = cl.storage
        let cursorLocation = cl.cursorLocation
        let lineRange = cl.lineRange
        let trimmedLine = cl.trimmedLine
        let fullRange = cl.fullRange

        let replacement: String

        if let match = Self.taskCheckedPattern.firstMatch(in: trimmedLine, range: fullRange) {
            // `- [x] content` → `- [ ] content`
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let marker = (trimmedLine as NSString).substring(with: match.range(at: 2))
            let content = (trimmedLine as NSString).substring(with: match.range(at: 3))
            replacement = "\(indent)\(marker) [ ] \(content)"
        } else if let match = Self.taskUncheckedPattern.firstMatch(in: trimmedLine, range: fullRange) {
            // `- [ ] content` → `- [x] content`
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let marker = (trimmedLine as NSString).substring(with: match.range(at: 2))
            let content = (trimmedLine as NSString).substring(with: match.range(at: 3))
            replacement = "\(indent)\(marker) [x] \(content)"
        } else if let match = Self.listItemPattern.firstMatch(in: trimmedLine, range: fullRange) {
            // `- content` → `- [ ] content`
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let marker = (trimmedLine as NSString).substring(with: match.range(at: 2))
            let content = (trimmedLine as NSString).substring(with: match.range(at: 3))
            replacement = "\(indent)\(marker) [ ] \(content)"
        } else if let match = Self.plainLinePattern.firstMatch(in: trimmedLine, range: fullRange) {
            // `content` → `- [ ] content`
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let content = (trimmedLine as NSString).substring(with: match.range(at: 2))
            replacement = "\(indent)- [ ] \(content)"
        } else if trimmedLine.isEmpty {
            // Empty line → insert `- [ ] `
            replacement = "- [ ] "
        } else {
            return
        }

        let replaceRange = NSRange(location: lineRange.location, length: (trimmedLine as NSString).length)
        let lengthDiff = (replacement as NSString).length - (trimmedLine as NSString).length

        if shouldChangeText(in: replaceRange, replacementString: replacement) {
            storage.replaceCharacters(in: replaceRange, with: replacement)
            let newCursor = max(lineRange.location, min(cursorLocation + lengthDiff, lineRange.location + (replacement as NSString).length))
            setSelectedRange(NSRange(location: newCursor, length: 0))
            didChangeText()
        }
    }

    // MARK: - Tab indentation for list items

    private static let indentUnit = "\t"

    override func insertTab(_ sender: Any?) {
        guard let cl = currentLine() else {
            super.insertTab(sender)
            return
        }

        guard isListItem(cl.trimmedLine, range: cl.fullRange) else {
            super.insertTab(sender)
            return
        }

        let insertRange = NSRange(location: cl.lineRange.location, length: 0)
        let indent = Self.indentUnit
        if shouldChangeText(in: insertRange, replacementString: indent) {
            cl.storage.replaceCharacters(in: insertRange, with: indent)
            let newCursor = cl.cursorLocation + (indent as NSString).length
            setSelectedRange(NSRange(location: newCursor, length: 0))
            didChangeText()
        }
    }

    override func insertBacktab(_ sender: Any?) {
        guard let cl = currentLine() else { return }
        guard isListItem(cl.trimmedLine, range: cl.fullRange) else { return }

        let indent = Self.indentUnit
        let indentLen = (indent as NSString).length
        let lineText = cl.nsString.substring(with: cl.lineRange)
        guard lineText.hasPrefix(indent) else { return }

        let removeRange = NSRange(location: cl.lineRange.location, length: indentLen)
        if shouldChangeText(in: removeRange, replacementString: "") {
            cl.storage.replaceCharacters(in: removeRange, with: "")
            let newCursor = max(cl.lineRange.location, cl.cursorLocation - indentLen)
            setSelectedRange(NSRange(location: newCursor, length: 0))
            didChangeText()
        }
    }

    // MARK: - List auto-continuation

    // swiftlint:disable force_try
    private static let unorderedListPattern = try! NSRegularExpression(
        pattern: #"^(\s*)([-*])\s(\[[ xX]\]\s)?(.*)$"#
    )
    private static let orderedListPattern = try! NSRegularExpression(
        pattern: #"^(\s*)(\d+)\.\s(.*)$"#
    )
    // swiftlint:enable force_try

    override func insertNewline(_ sender: Any?) {
        guard let cl = currentLine() else {
            super.insertNewline(sender)
            return
        }
        let storage = cl.storage
        let cursorLocation = cl.cursorLocation
        let lineRange = cl.lineRange

        // If cursor is at the very beginning of the line, just insert a plain newline
        // to avoid duplicating the list marker prefix (e.g. "- [ ]")
        if cursorLocation == lineRange.location {
            super.insertNewline(sender)
            return
        }

        let trimmedLine = cl.trimmedLine
        let fullRange = cl.fullRange

        // Try unordered / task list
        if let match = Self.unorderedListPattern.firstMatch(in: trimmedLine, range: fullRange) {
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let marker = (trimmedLine as NSString).substring(with: match.range(at: 2))
            let hasCheckbox = match.range(at: 3).location != NSNotFound
            let content = (trimmedLine as NSString).substring(with: match.range(at: 4))

            if content.isEmpty {
                // Empty list item → remove marker, end list
                if shouldChangeText(in: lineRange, replacementString: "") {
                    storage.replaceCharacters(in: lineRange, with: "")
                    setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    didChangeText()
                }
                return
            }

            let nextMarker: String
            if hasCheckbox {
                nextMarker = "\(indent)\(marker) [ ] "
            } else {
                nextMarker = "\(indent)\(marker) "
            }

            let insertText = "\n\(nextMarker)"
            let insertRange = NSRange(location: cursorLocation, length: 0)
            if shouldChangeText(in: insertRange, replacementString: insertText) {
                storage.replaceCharacters(in: insertRange, with: insertText)
                setSelectedRange(NSRange(location: cursorLocation + (insertText as NSString).length, length: 0))
                didChangeText()
            }
            return
        }

        // Try ordered list
        if let match = Self.orderedListPattern.firstMatch(in: trimmedLine, range: fullRange) {
            let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
            let numberStr = (trimmedLine as NSString).substring(with: match.range(at: 2))
            let content = (trimmedLine as NSString).substring(with: match.range(at: 3))

            if content.isEmpty {
                // Empty list item → remove marker, end list
                if shouldChangeText(in: lineRange, replacementString: "") {
                    storage.replaceCharacters(in: lineRange, with: "")
                    setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    didChangeText()
                }
                return
            }

            let nextNumber = (Int(numberStr) ?? 0) + 1
            let nextMarker = "\(indent)\(nextNumber). "
            let insertText = "\n\(nextMarker)"
            let insertRange = NSRange(location: cursorLocation, length: 0)
            if shouldChangeText(in: insertRange, replacementString: insertText) {
                storage.replaceCharacters(in: insertRange, with: insertText)
                setSelectedRange(NSRange(location: cursorLocation + (insertText as NSString).length, length: 0))
                didChangeText()
            }
            return
        }

        // No list marker → default newline
        super.insertNewline(sender)
    }
}
