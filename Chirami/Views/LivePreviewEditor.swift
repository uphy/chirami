import SwiftUI
import AppKit

/// NSViewRepresentable wrapping NSTextView with Markdown live preview.
struct LivePreviewEditor: NSViewRepresentable {
    @Binding var text: String
    var backgroundColor: NSColor = .white
    var noteColor: NoteColor = .yellow
    var fontSize: CGFloat = 14
    var fontName: String?
    var noteURL: URL?
    var attachmentsDir: URL?
    var isReadOnly: Bool = false
    var editorState: EditorStatePreservable?
    var onFontSizeChange: ((CGFloat) -> Void)?
    var onTogglePin: (() -> Void)?
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
        textView.isEditable = !isReadOnly
        textView.isRichText = true
        textView.allowsUndo = !isReadOnly
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        if let fontName, let customFont = NSFont(name: fontName, size: fontSize) {
            textView.font = customFont
        } else {
            textView.font = NSFont.systemFont(ofSize: fontSize)
        }
        if let layoutManager = textView.layoutManager as? BulletLayoutManager {
            layoutManager.fontName = fontName
        }
        textView.currentFontSize = fontSize
        textView.backgroundColor = backgroundColor.withAlphaComponent(0)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.selectedTextAttributes = [.backgroundColor: noteColor.selectionColor]

        let coordinator = context.coordinator
        textView.onCheckboxClick = { [weak coordinator] charIndex in
            coordinator?.toggleCheckbox(at: charIndex)
        }
        textView.onFontSizeChange = { [weak coordinator] newSize in
            coordinator?.handleFontSizeChange(newSize)
        }
        textView.onTogglePin = onTogglePin
        textView.customMenuItems = customMenuItems
        textView.noteURL = noteURL
        textView.attachmentsDir = attachmentsDir
        textView.onMouseHoverLineChanged = { [weak coordinator] line in
            coordinator?.handleMouseHoverLineChanged(line)
        }
        textView.onUnfoldLine = { [weak coordinator] line in
            coordinator?.toggleFold(line: line)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        context.coordinator.editorState = editorState

        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )

        // Track scroll position changes for editor state persistence
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // Restore cursor/scroll from editorState (guards against SwiftUI view recreation).
        if let editorState = editorState {
            context.coordinator.deferredRestoreEditorState(
                cursorLocation: editorState.savedCursorLocation,
                scrollOffset: editorState.savedScrollOffset
            )
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        let coordinator = context.coordinator

        // Update note URL and attachments dir
        textView.noteURL = noteURL
        textView.attachmentsDir = attachmentsDir

        // Update note color if changed (e.g., via color picker)
        var needsRestyle = false
        if coordinator.noteURL != noteURL {
            coordinator.noteURL = noteURL
            needsRestyle = true
        }
        if coordinator.noteColor != noteColor {
            coordinator.noteColor = noteColor
            needsRestyle = true
        }

        // Update font name if changed
        if coordinator.fontName != fontName {
            coordinator.fontName = fontName
            if let layoutManager = textView.layoutManager as? BulletLayoutManager {
                layoutManager.fontName = fontName
            }
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
            textView.selectedTextAttributes = [.backgroundColor: noteColor.selectionColor]
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
        Coordinator(text: $text, noteColor: noteColor, fontSize: fontSize, fontName: fontName, noteURL: noteURL, isReadOnly: isReadOnly, onFontSizeChange: onFontSizeChange)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isApplyingStyling = false
        weak var textView: NSTextView?
        weak var editorState: EditorStatePreservable?
        private let overlayManager = TableOverlayManager()

        var isWindowFocused = true
        var noteColor: NoteColor {
            didSet { styler = MarkdownStyler(noteColor: noteColor, baseFontSize: fontSize, fontName: fontName) }
        }
        var fontSize: CGFloat {
            didSet { styler = MarkdownStyler(noteColor: noteColor, baseFontSize: fontSize, fontName: fontName) }
        }
        var fontName: String? {
            didSet { styler = MarkdownStyler(noteColor: noteColor, baseFontSize: fontSize, fontName: fontName) }
        }
        var noteURL: URL? {
            didSet {
                if noteURL != oldValue, let path = noteURL?.path {
                    foldedLines = AppState.shared.foldingState(for: path).foldedLines
                }
            }
        }
        let isReadOnly: Bool
        var onFontSizeChange: ((CGFloat) -> Void)?
        private var styler: MarkdownStyler
        private var lastCursorLocation: Int = 0
        private var isRestoringEditorState = false
        private var lastStyledText: String = ""

        // MARK: - Fold state
        var foldedLines: Set<Int> = [] {
            didSet {
                (textView as? MarkdownTextView)?.foldedLines = foldedLines
            }
        }
        private var foldButtons: [NSButton] = []
        private var cachedFoldableStartLines: Set<Int> = []
        private var cachedLineStarts: [Int] = [0]
        private var hoveredLine: Int?
        private var foldButtonImageRight: NSImage?
        private var foldButtonImageDown: NSImage?

        init(text: Binding<String>, noteColor: NoteColor, fontSize: CGFloat, fontName: String? = nil, noteURL: URL?, isReadOnly: Bool, onFontSizeChange: ((CGFloat) -> Void)?) {
            self.text = text
            self.noteColor = noteColor
            self.fontSize = fontSize
            self.fontName = fontName
            self.noteURL = noteURL
            self.isReadOnly = isReadOnly
            self.onFontSizeChange = onFontSizeChange
            self.styler = MarkdownStyler(noteColor: noteColor, baseFontSize: fontSize, fontName: fontName)
            if let path = noteURL?.path {
                self.foldedLines = AppState.shared.foldingState(for: path).foldedLines
            }
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
            overlayManager.removeAll()
            foldButtons.forEach { $0.removeFromSuperview() }
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func windowDidResignKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  let textView = textView,
                  textView.window === window else { return }

            // Save cursor and scroll position before losing focus
            if let editorState = editorState {
                editorState.savedCursorLocation = textView.selectedRange().location
                if let scrollView = textView.enclosingScrollView {
                    editorState.savedScrollOffset = scrollView.contentView.bounds.origin
                }
            }

            isWindowFocused = false
            applyStyling(to: textView)
        }

        @objc func textViewFrameDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            overlayManager.update(textView: textView, noteColor: noteColor, fontSize: fontSize)
            applyStyling(to: textView)
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView else { return }
            editorState?.savedScrollOffset = clipView.bounds.origin
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  let textView = textView,
                  textView.window === window else { return }
            isWindowFocused = true

            if let editorState = editorState {
                // Capture values before makeFirstResponder (called after this notification)
                // can reset the cursor and trigger textViewDidChangeSelection.
                deferredRestoreEditorState(
                    cursorLocation: editorState.savedCursorLocation,
                    scrollOffset: editorState.savedScrollOffset
                )
            } else {
                applyStyling(to: textView)
            }
        }

        /// Defers cursor/scroll restoration to run after NotePanel.becomeKey() finishes
        /// its makeFirstResponder call (which resets the cursor to 0).
        func deferredRestoreEditorState(cursorLocation: Int, scrollOffset: CGPoint) {
            isRestoringEditorState = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.textView else { return }
                let loc = min(cursorLocation, textView.string.utf16.count)
                textView.setSelectedRange(NSRange(location: loc, length: 0))
                self.lastCursorLocation = loc
                self.editorState?.savedCursorLocation = loc
                self.isRestoringEditorState = false
                self.applyStyling(to: textView)

                if let scrollView = textView.enclosingScrollView {
                    scrollView.contentView.scroll(to: scrollOffset)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if textView.hasMarkedText() { return }
            text.wrappedValue = textView.string
            applyStyling(to: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingStyling else { return }
            guard !isRestoringEditorState else { return }
            guard let textView = notification.object as? NSTextView else { return }
            if textView.hasMarkedText() { return }
            if let mdTextView = textView as? MarkdownTextView,
               mdTextView.isAdjustingCursorForHiddenPrefix {
                lastCursorLocation = textView.selectedRange().location
                return
            }
            let newLocation = textView.selectedRange().location
            if newLocation != lastCursorLocation {
                lastCursorLocation = newLocation
                editorState?.savedCursorLocation = newLocation
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

            // Provide note base URL for relative image path resolution
            if let noteURL {
                styler.noteBaseURL = noteURL.deletingLastPathComponent()
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
            let cursorLocation = (isWindowFocused && !isReadOnly) ? textView.selectedRange().location : NSNotFound
            let safeLocation = (isWindowFocused && !isReadOnly) ? min(cursorLocation, text.utf16.count) : NSNotFound

            let styled = styler.style(text, cursorLocation: safeLocation, foldedLines: foldedLines)

            // Refresh cached foldable blocks from the document already parsed by style()
            if text != lastStyledText {
                lastStyledText = text
                cachedFoldableStartLines = Set(styler.lastFoldableBlocks.map { $0.startLine })
                cachedLineStarts = buildLineStarts(in: text as NSString)
                if !foldedLines.isEmpty, let notePath = noteURL?.path {
                    AppState.shared.validateFoldingState(for: notePath, validLines: cachedFoldableStartLines)
                    foldedLines = AppState.shared.foldingState(for: notePath).foldedLines
                }
                // Sync line starts cache to textView for hover detection
                if let mdTextView = textView as? MarkdownTextView {
                    mdTextView.lineStartsForHover = cachedLineStarts
                }
            }

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

            // Sync typingAttributes to the style at the cursor position
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
            overlayManager.update(textView: textView, noteColor: noteColor, fontSize: fontSize)
            textView.needsDisplay = true
            textView.updateInsertionPointStateAndRestartTimer(true)

            // Update fold buttons
            updateFoldButtons(in: textView, text: text, hoveredLine: hoveredLine)
        }

        // MARK: - Fold buttons

        private func updateFoldButtons(in textView: NSTextView, text: String, hoveredLine: Int?) {
            guard let layoutManager = textView.layoutManager,
                  !cachedFoldableStartLines.isEmpty else {
                hideAllFoldButtons()
                return
            }

            let lineStarts = cachedLineStarts

            // Collect lines that need a button:
            // 1. All folded lines (always visible)
            // 2. Hovered line if it's a foldable block and not folded
            var linesToShow: [(line: Int, isFolded: Bool)] = []
            for foldedLine in foldedLines where cachedFoldableStartLines.contains(foldedLine) {
                linesToShow.append((foldedLine, true))
            }
            if let hoveredLine,
               cachedFoldableStartLines.contains(hoveredLine),
               !foldedLines.contains(hoveredLine) {
                linesToShow.append((hoveredLine, false))
            }
            let inset = textView.textContainerInset
            let buttonSize: CGFloat = 14
            var visibleCount = 0

            let nsLength = (text as NSString).length
            for entry in linesToShow {
                guard entry.line - 1 < lineStarts.count else { continue }
                let lineCharOffset = lineStarts[entry.line - 1]
                // Use a character from the middle of the line to avoid hidden prefix glyphs
                // (list item prefixes like "- [ ] " have near-zero font size and may confuse layout queries)
                let nextLineStart = entry.line < lineStarts.count ? lineStarts[entry.line] : nsLength
                let midOffset = min(lineCharOffset + (nextLineStart - lineCharOffset) / 2, max(0, nsLength - 1))
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: midOffset)
                guard glyphIndex < layoutManager.numberOfGlyphs else { continue }
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                guard lineRect.height > 1 else { continue }

                let buttonX = max(0, inset.width - buttonSize - 2)
                let buttonY = inset.height + lineRect.origin.y + (lineRect.height - buttonSize) / 2

                let button = foldButton(at: visibleCount, in: textView)
                button.frame = NSRect(x: buttonX, y: buttonY, width: buttonSize, height: buttonSize)
                button.image = entry.isFolded ? foldButtonImage(folded: true) : foldButtonImage(folded: false)
                button.contentTintColor = NSColor.tertiaryLabelColor
                button.tag = entry.line
                button.isHidden = false
                visibleCount += 1
            }

            // Hide unused buttons
            for i in visibleCount..<foldButtons.count {
                foldButtons[i].isHidden = true
            }
        }

        /// Handles mouse hover line changes from MarkdownTextView.
        /// Only updates fold buttons (no full restyling).
        func handleMouseHoverLineChanged(_ line: Int?) {
            guard hoveredLine != line else { return }
            hoveredLine = line
            guard let textView = textView else { return }
            updateFoldButtons(in: textView, text: textView.string, hoveredLine: hoveredLine)
        }

        /// Builds array of character offsets for line starts (0-indexed: index 0 = line 1).
        private func buildLineStarts(in nsText: NSString) -> [Int] {
            var starts = [0]
            for i in 0..<nsText.length {
                if nsText.character(at: i) == 0x0A, i + 1 <= nsText.length {
                    starts.append(i + 1)
                }
            }
            return starts
        }

        /// Returns a cached fold button image.
        private func foldButtonImage(folded: Bool) -> NSImage? {
            if folded {
                if foldButtonImageRight == nil {
                    let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
                    foldButtonImageRight = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                        .withSymbolConfiguration(config)
                }
                return foldButtonImageRight
            } else {
                if foldButtonImageDown == nil {
                    let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
                    foldButtonImageDown = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                        .withSymbolConfiguration(config)
                }
                return foldButtonImageDown
            }
        }

        /// Returns a reusable button from the pool, creating one if needed.
        private func foldButton(at index: Int, in textView: NSTextView) -> NSButton {
            if index < foldButtons.count {
                return foldButtons[index]
            }
            let button = NSButton(frame: .zero)
            button.bezelStyle = .inline
            button.isBordered = false
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(foldToggleButtonClicked(_:))
            textView.addSubview(button)
            foldButtons.append(button)
            return button
        }

        private func hideAllFoldButtons() {
            foldButtons.forEach { $0.isHidden = true }
        }

        @objc private func foldToggleButtonClicked(_ sender: NSButton) {
            toggleFold(line: sender.tag)
        }

        func toggleFold(line: Int) {
            guard let notePath = noteURL?.path, let textView = textView else { return }
            AppState.shared.toggleFoldedLine(line, for: notePath)
            foldedLines = AppState.shared.foldingState(for: notePath).foldedLines
            applyStyling(to: textView)
        }
    }
}
