import SwiftUI
import AppKit

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
        private let overlayManager = TableOverlayManager()

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
            overlayManager.removeAll()
            NotificationCenter.default.removeObserver(self)
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
            overlayManager.update(textView: textView, noteColor: noteColor, fontSize: fontSize)
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
            if let mdTextView = textView as? MarkdownTextView,
               mdTextView.isAdjustingCursorForHiddenPrefix {
                lastCursorLocation = textView.selectedRange().location
                return
            }
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
        }
    }
}
