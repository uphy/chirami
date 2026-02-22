import SwiftUI
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

        var foundIndex: Int? = nil
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
        "'": ("'", "'"),
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

    private static let unorderedListPattern = try! NSRegularExpression(
        pattern: #"^(\s*)([-*])\s(\[[ xX]\]\s)?(.*)$"#
    )
    private static let orderedListPattern = try! NSRegularExpression(
        pattern: #"^(\s*)(\d+)\.\s(.*)$"#
    )

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

/// NSViewRepresentable wrapping NSTextView with Markdown live preview.
struct LivePreviewEditor: NSViewRepresentable {
    @Binding var text: String
    var backgroundColor: NSColor = .white
    var noteColor: NoteColor = .yellow
    var fontSize: CGFloat = 14
    var onFontSizeChange: ((CGFloat) -> Void)?
    var customMenuItems: (() -> [NSMenuItem])?

    func makeNSView(context: Context) -> NSScrollView {
        // Build MarkdownTextView manually instead of NSTextView.scrollableTextView()
        let textStorage = NSTextStorage()
        let layoutManager = BulletLayoutManager()
        layoutManager.baseFontSize = fontSize
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.currentFontSize = fontSize
        textView.backgroundColor = backgroundColor.withAlphaComponent(0)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        let coordinator = context.coordinator
        textView.onCheckboxClick = { [weak coordinator] charIndex in
            coordinator?.toggleCheckbox(at: charIndex)
        }
        textView.onFontSizeChange = { [weak coordinator] newSize in
            coordinator?.handleFontSizeChange(newSize)
        }
        textView.customMenuItems = customMenuItems

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        context.coordinator.textView = textView

        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        let coordinator = context.coordinator

        // Update note color if changed (e.g., via color picker)
        var needsRestyle = false
        if coordinator.noteColor != noteColor {
            coordinator.noteColor = noteColor
            needsRestyle = true
        }

        // Update font size if changed
        if coordinator.fontSize != fontSize {
            coordinator.fontSize = fontSize
            textView.currentFontSize = fontSize
            if let layoutManager = textView.layoutManager as? BulletLayoutManager {
                layoutManager.baseFontSize = fontSize
            }
            needsRestyle = true
        }

        if needsRestyle {
            coordinator.applyStyling(to: textView)
        }

        // Only update if text changed externally (e.g., file watcher)
        // Use hasMarkedText() instead of isEditing to avoid blocking external updates
        // while the window has focus. hasMarkedText() only blocks during IME composition.
        if textView.string != text && !textView.hasMarkedText() {
            let savedSelection = textView.selectedRange()
            textView.string = text
            // Restore cursor position, clamped to new text length
            let clampedLocation = min(savedSelection.location, textView.string.utf16.count)
            let clampedLength = min(savedSelection.length, max(0, textView.string.utf16.count - clampedLocation))
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            coordinator.applyStyling(to: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, noteColor: noteColor, fontSize: fontSize, onFontSizeChange: onFontSizeChange)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isApplyingStyling = false
        weak var textView: NSTextView?
        private var tableOverlays: [Int: TableOverlayView] = [:]  // key = range.location

        var isWindowFocused = true
        var noteColor: NoteColor {
            didSet { styler = MarkdownStyler(noteColor: noteColor, baseFontSize: fontSize) }
        }
        var fontSize: CGFloat {
            didSet { styler = MarkdownStyler(noteColor: noteColor, baseFontSize: fontSize) }
        }
        var onFontSizeChange: ((CGFloat) -> Void)?
        private var styler: MarkdownStyler
        private var lastCursorLocation: Int = 0

        init(text: Binding<String>, noteColor: NoteColor, fontSize: CGFloat, onFontSizeChange: ((CGFloat) -> Void)?) {
            self.text = text
            self.noteColor = noteColor
            self.fontSize = fontSize
            self.onFontSizeChange = onFontSizeChange
            self.styler = MarkdownStyler(noteColor: noteColor, baseFontSize: fontSize)
            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey(_:)),
                name: NSWindow.didBecomeKeyNotification,
                object: nil
            )
        }

        deinit {
            removeAllTableOverlays()
            NotificationCenter.default.removeObserver(self)
        }

        // MARK: - Table overlay lifecycle

        private func removeAllTableOverlays() {
            for overlay in tableOverlays.values {
                overlay.removeFromSuperview()
            }
            tableOverlays.removeAll()
        }

        private func updateTableOverlays(textView: NSTextView) {
            guard let storage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)

            let storageRange = NSRange(location: 0, length: storage.length)

            // Collect tableOverlay attributes using longestEffectiveRange to avoid
            // attribute run fragmentation caused by tableSeparatorRow splitting the range.
            var found: [Int: TableOverlayData] = [:]
            storage.enumerateAttribute(.tableOverlay, in: storageRange, options: []) { value, range, _ in
                guard let data = value as? TableOverlayData else { return }
                var fullRange = NSRange()
                storage.attribute(.tableOverlay, at: range.location,
                                  longestEffectiveRange: &fullRange,
                                  in: storageRange)
                found[fullRange.location] = data
            }

            // Remove overlays no longer present
            let existingKeys = Set(tableOverlays.keys)
            let foundKeys = Set(found.keys)
            for key in existingKeys.subtracting(foundKeys) {
                tableOverlays[key]?.removeFromSuperview()
                tableOverlays.removeValue(forKey: key)
            }

            let containerOrigin = textView.textContainerOrigin
            let containerWidth = textContainer.size.width

            // Create or update overlays
            for (location, data) in found {
                // Use longestEffectiveRange to get the full table range
                var effectiveRange = NSRange()
                guard storage.attribute(.tableOverlay, at: location,
                                        longestEffectiveRange: &effectiveRange,
                                        in: storageRange) != nil
                else { continue }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: effectiveRange, actualCharacterRange: nil)

                // Collect per-row rects, skipping separator rows
                var rowRects: [NSRect] = []
                layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, _ in
                    let lineCharRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
                    if lineCharRange.length > 0,
                       storage.attribute(.tableSeparatorRow, at: lineCharRange.location, effectiveRange: nil) != nil {
                        return  // skip separator
                    }
                    rowRects.append(lineRect)
                }

                guard let firstRect = rowRects.first, let lastRect = rowRects.last else { continue }
                let minY = firstRect.minY
                let maxY = lastRect.maxY
                guard minY < maxY else { continue }

                let naturalWidths = TableOverlayView.computeColumnWidths(data: data)
                let tableWidth = naturalWidths.reduce(0, +)
                let overlayWidth = tableWidth > 0 ? min(tableWidth, containerWidth) : containerWidth

                let overlayFrame = NSRect(
                    x: containerOrigin.x,
                    y: containerOrigin.y + minY,
                    width: overlayWidth,
                    height: maxY - minY
                )

                // Convert to overlay-local coordinates (y=0 at top of overlay)
                let localRowRects = rowRects.map { rect in
                    NSRect(x: 0, y: rect.minY - minY, width: overlayWidth, height: rect.height)
                }

                if let existing = tableOverlays[location] {
                    existing.frame = overlayFrame
                    existing.data = data
                    existing.noteColor = noteColor
                    existing.baseFontSize = fontSize
                    existing.rowRects = localRowRects
                    existing.needsDisplay = true
                } else {
                    let overlay = TableOverlayView(data: data, noteColor: noteColor, baseFontSize: fontSize)
                    overlay.frame = overlayFrame
                    overlay.rowRects = localRowRects
                    textView.addSubview(overlay)
                    tableOverlays[location] = overlay
                }
            }
        }

        @objc private func windowDidResignKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  let textView = textView,
                  textView.window === window else { return }
            isWindowFocused = false
            applyStyling(to: textView)
        }

        @objc func textViewFrameDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            updateTableOverlays(textView: textView)
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  let textView = textView,
                  textView.window === window else { return }
            isWindowFocused = true
            applyStyling(to: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if textView.hasMarkedText() { return }
            text.wrappedValue = textView.string
            applyStyling(to: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingStyling else { return }
            guard let textView = notification.object as? NSTextView else { return }
            if textView.hasMarkedText() { return }
            let newLocation = textView.selectedRange().location
            if newLocation != lastCursorLocation {
                lastCursorLocation = newLocation
                applyStyling(to: textView)
            }
        }

        func handleFontSizeChange(_ newSize: CGFloat) {
            fontSize = newSize
            if let textView = textView {
                applyStyling(to: textView)
            }
            onFontSizeChange?(newSize)
        }

        func toggleCheckbox(at charIndex: Int) {
            guard let textView = textView,
                  let storage = textView.textStorage else { return }

            // Find the line containing charIndex and search for the checkbox pattern
            let nsString = storage.string as NSString
            let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
            let lineText = nsString.substring(with: lineRange) as NSString

            let replacement: String
            let replaceRange: NSRange
            let uncheckedPos = lineText.range(of: "[ ]")
            let checkedPos = lineText.range(of: "[x]")
            let checkedPosUpper = lineText.range(of: "[X]")

            if uncheckedPos.location != NSNotFound {
                replacement = "[x]"
                replaceRange = NSRange(location: lineRange.location + uncheckedPos.location, length: 3)
            } else if checkedPos.location != NSNotFound {
                replacement = "[ ]"
                replaceRange = NSRange(location: lineRange.location + checkedPos.location, length: 3)
            } else if checkedPosUpper.location != NSNotFound {
                replacement = "[ ]"
                replaceRange = NSRange(location: lineRange.location + checkedPosUpper.location, length: 3)
            } else {
                return
            }

            // Use shouldChangeText/didChangeText for Undo support
            if textView.shouldChangeText(in: replaceRange, replacementString: replacement) {
                storage.replaceCharacters(in: replaceRange, with: replacement)
                textView.didChangeText()
                text.wrappedValue = storage.string
                applyStyling(to: textView)
            }
        }

        func applyStyling(to textView: NSTextView) {
            guard !isApplyingStyling else { return }
            guard let storage = textView.textStorage else { return }
            if let layoutManager = textView.layoutManager as? BulletLayoutManager {
                layoutManager.baseFontSize = fontSize
            }

            // Provide current container width for image scaling
            if let width = textView.textContainer?.size.width, width > 0 {
                styler.containerWidth = width
            }

            // Re-apply styling when async images finish loading
            styler.onImageLoaded = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.applyStyling(to: textView)
            }

            let text = storage.string
            let cursorLocation = isWindowFocused ? textView.selectedRange().location : NSNotFound
            let safeLocation = isWindowFocused ? min(cursorLocation, text.utf16.count) : NSNotFound

            let styled = styler.style(text, cursorLocation: safeLocation)

            // Preserve cursor/selection while applying attributes
            let savedRange = textView.selectedRange()

            isApplyingStyling = true
            storage.beginEditing()
            styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length)) { attrs, range, _ in
                storage.setAttributes(attrs, range: range)
            }
            storage.endEditing()

            // Restore selection (setSelectedRange may fire textViewDidChangeSelection,
            // which is suppressed by isApplyingStyling)
            let restoredRange = NSRange(
                location: min(savedRange.location, storage.length),
                length: min(savedRange.length, max(0, storage.length - savedRange.location))
            )
            textView.setSelectedRange(restoredRange)

            // カーソル位置のスタイルに typingAttributes を同期
            let cursorPos = restoredRange.location
            if styled.length == 0 {
                textView.typingAttributes = styler.baseAttributes
            } else if cursorPos < styled.length {
                textView.typingAttributes = styled.attributes(at: cursorPos, effectiveRange: nil)
            } else {
                let lastCharIndex = styled.length - 1
                let lastChar = (styled.string as NSString).substring(with: NSRange(location: lastCharIndex, length: 1))
                if lastChar == "\n" {
                    textView.typingAttributes = styler.baseAttributes
                } else {
                    textView.typingAttributes = styled.attributes(at: lastCharIndex, effectiveRange: nil)
                }
            }

            isApplyingStyling = false
            updateTableOverlays(textView: textView)
            textView.needsDisplay = true
        }
    }
}
