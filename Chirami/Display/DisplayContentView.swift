import AppKit

/// A scrollable text view that renders Markdown content using BulletLayoutManager and MarkdownStyler.
/// In read-only mode: full rendering via styleAll. In editable mode: live preview.
class DisplayContentView: NSView, NSTextViewDelegate {

    private let textView: NSTextView
    private let scrollView: NSScrollView
    private let styler: MarkdownStyler
    private let isReadOnly: Bool
    private let contentModel: DisplayContentModel?

    private var isApplyingStyling = false
    private var lastCursorLocation = 0

    init(content: String, fileURL: URL?, isReadOnly: Bool) {
        self.isReadOnly = isReadOnly

        let layoutManager = BulletLayoutManager()
        layoutManager.baseFontSize = 14

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = !isReadOnly
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = !isReadOnly
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        self.textView = textView
        self.scrollView = scrollView
        self.styler = MarkdownStyler(noteColor: .yellow, baseFontSize: 14)
        self.contentModel = (fileURL != nil && !isReadOnly) ? DisplayContentModel(fileURL: fileURL!, initialContent: content) : nil

        super.init(frame: .zero)

        textView.delegate = self

        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // Set initial content and apply styling
        textView.string = content
        applyStyling(to: textView, text: content)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Styling

    private func applyStyling(to textView: NSTextView, text: String) {
        guard !isApplyingStyling, let storage = textView.textStorage else { return }

        let styled: NSAttributedString
        if isReadOnly {
            styled = styler.styleAll(text)
        } else {
            let cursorLocation = textView.selectedRange().location
            styled = styler.style(text, cursorLocation: cursorLocation)
        }

        let savedRange = textView.selectedRange()

        isApplyingStyling = true
        storage.beginEditing()
        styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length)) { attrs, range, _ in
            storage.setAttributes(attrs, range: range)
        }
        storage.endEditing()

        if !isReadOnly {
            let restoredRange = NSRange(
                location: min(savedRange.location, storage.length),
                length: min(savedRange.length, max(0, storage.length - savedRange.location))
            )
            textView.setSelectedRange(restoredRange)
        }
        isApplyingStyling = false
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView === self.textView else { return }
        if textView.hasMarkedText() { return }
        let text = textView.string
        contentModel?.save(text: text)
        applyStyling(to: textView, text: text)
        lastCursorLocation = textView.selectedRange().location
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingStyling else { return }
        guard let textView = notification.object as? NSTextView,
              textView === self.textView,
              !isReadOnly else { return }
        if textView.hasMarkedText() { return }
        let newLocation = textView.selectedRange().location
        if newLocation != lastCursorLocation {
            lastCursorLocation = newLocation
            applyStyling(to: textView, text: textView.string)
        }
    }
}
