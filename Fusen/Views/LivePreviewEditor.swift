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
        if isOverCheckbox(at: point) || isOverLink(at: point) {
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

    private func isOverLink(at point: NSPoint) -> Bool {
        return linkURL(at: point) != nil
    }

    private func linkURL(at point: NSPoint) -> URL? {
        guard let storage = textStorage else { return nil }
        let charIndex = characterIndexForInsertion(at: point)
        guard charIndex < storage.length else { return nil }
        return storage.attribute(.link, at: charIndex, effectiveRange: nil) as? URL
    }

    private func isOverCheckbox(at point: NSPoint) -> Bool {
        return charIndexOfCheckbox(at: point) != nil
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
        return nil
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

    // MARK: - Toggle task list (Cmd+L)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let chars = event.charactersIgnoringModifiers {
            if chars == "l" {
                toggleTaskList()
                return true
            }
            // Cmd+= (or Cmd+Shift+=, i.e. Cmd++) to increase font size
            if chars == "=" || chars == "+" {
                let newSize = min(currentFontSize + 1, 32)
                if newSize != currentFontSize {
                    currentFontSize = newSize
                    onFontSizeChange?(newSize)
                }
                return true
            }
            // Cmd+- to decrease font size
            if chars == "-" {
                let newSize = max(currentFontSize - 1, 8)
                if newSize != currentFontSize {
                    currentFontSize = newSize
                    onFontSizeChange?(newSize)
                }
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
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
        guard let storage = textStorage else { return }

        let nsString = storage.string as NSString
        let cursorLocation = selectedRange().location
        let lineRange = nsString.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let lineText = nsString.substring(with: lineRange)
        let trimmedLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
        let fullRange = NSRange(location: 0, length: (trimmedLine as NSString).length)

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
        guard let storage = textStorage else {
            super.insertTab(sender)
            return
        }

        let nsString = storage.string as NSString
        let cursorLocation = selectedRange().location
        let lineRange = nsString.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let lineText = nsString.substring(with: lineRange)
        let trimmedLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
        let fullRange = NSRange(location: 0, length: (trimmedLine as NSString).length)

        let isListItem = Self.unorderedListPattern.firstMatch(in: trimmedLine, range: fullRange) != nil
            || Self.orderedListPattern.firstMatch(in: trimmedLine, range: fullRange) != nil

        guard isListItem else {
            super.insertTab(sender)
            return
        }

        let insertRange = NSRange(location: lineRange.location, length: 0)
        let indent = Self.indentUnit
        if shouldChangeText(in: insertRange, replacementString: indent) {
            storage.replaceCharacters(in: insertRange, with: indent)
            let newCursor = cursorLocation + (indent as NSString).length
            setSelectedRange(NSRange(location: newCursor, length: 0))
            didChangeText()
        }
    }

    override func insertBacktab(_ sender: Any?) {
        guard let storage = textStorage else { return }

        let nsString = storage.string as NSString
        let cursorLocation = selectedRange().location
        let lineRange = nsString.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let lineText = nsString.substring(with: lineRange)
        let trimmedLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
        let fullRange = NSRange(location: 0, length: (trimmedLine as NSString).length)

        let isListItem = Self.unorderedListPattern.firstMatch(in: trimmedLine, range: fullRange) != nil
            || Self.orderedListPattern.firstMatch(in: trimmedLine, range: fullRange) != nil

        guard isListItem else { return }

        // Remove one leading tab if present
        let indent = Self.indentUnit
        let indentLen = (indent as NSString).length
        guard lineText.hasPrefix(indent) else { return }

        let removeRange = NSRange(location: lineRange.location, length: indentLen)
        if shouldChangeText(in: removeRange, replacementString: "") {
            storage.replaceCharacters(in: removeRange, with: "")
            let newCursor = max(lineRange.location, cursorLocation - indentLen)
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
        guard let storage = textStorage else {
            super.insertNewline(sender)
            return
        }

        let nsString = storage.string as NSString
        let cursorLocation = selectedRange().location
        let lineRange = nsString.lineRange(for: NSRange(location: cursorLocation, length: 0))

        // If cursor is at the very beginning of the line, just insert a plain newline
        // to avoid duplicating the list marker prefix (e.g. "- [ ]")
        if cursorLocation == lineRange.location {
            super.insertNewline(sender)
            return
        }

        let lineText = nsString.substring(with: lineRange)
        // Strip trailing newline for matching
        let trimmedLine = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText

        let fullRange = NSRange(location: 0, length: (trimmedLine as NSString).length)

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
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func windowDidResignKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  let textView = textView,
                  textView.window === window else { return }
            isWindowFocused = false
            applyStyling(to: textView)
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
            textView.needsDisplay = true
        }
    }
}
