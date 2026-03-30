import AppKit
import Markdown

/// Converts a Markdown document into a styled NSAttributedString.
/// Blocks containing the cursor are shown as raw Markdown; others are rendered.
///
/// The implementation is split across extension files by responsibility:
/// - `MarkdownStyler+Attributes.swift` — Custom NSAttributedString.Key definitions
/// - `MarkdownStyler+RangeUtils.swift` — Source location / NSRange conversion, line enumeration
/// - `MarkdownStyler+Inline.swift` — Inline pattern matching (bold, italic, code, links, etc.)
/// - `MarkdownStyler+Heading.swift` — Heading styling
/// - `MarkdownStyler+CodeBlock.swift` — Code block styling with syntax highlighting
/// - `MarkdownStyler+BlockQuote.swift` — Block quote styling
/// - `MarkdownStyler+List.swift` — List / task list styling
/// - `MarkdownStyler+Table.swift` — GFM table styling
class MarkdownStyler {

    let colorScheme: NoteColorScheme
    let baseFontSize: CGFloat
    let fontName: String?

    /// Width of the text container; used to compute scaled image heights for paragraph layout.
    var containerWidth: CGFloat = 380

    /// Called on the main thread when an async image finishes loading. Trigger re-styling here.
    var onImageLoaded: (() -> Void)?

    /// Parent directory of the note file. Used to resolve relative image paths.
    var noteBaseURL: URL?

    static let hiddenAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.clear,
        .font: NSFont.systemFont(ofSize: 0.001)
    ]

    /// Pre-computed line-start indices for the current style pass. Populated by style(_:cursorLocation:).
    var lineStartCache: [String.Index] = []

    init(colorScheme: NoteColorScheme = .yellow, baseFontSize: CGFloat = 14, fontName: String? = nil) {
        self.colorScheme = colorScheme
        self.baseFontSize = baseFontSize
        self.fontName = fontName
    }

    // MARK: - Font helpers

    func bodyFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let fontName, let font = NSFont(name: fontName, size: size) {
            if weight == .bold {
                return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    func boldFont(size: CGFloat) -> NSFont {
        bodyFont(size: size, weight: .bold)
    }

    func italicFont(size: CGFloat) -> NSFont {
        if let fontName, let font = NSFont(name: fontName, size: size) {
            return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return NSFontManager.shared.convert(
            NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask
        )
    }

    func monoFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let fontName, let font = NSFont(name: fontName, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: - Public

    /// Style `text` with all blocks fully rendered (no raw Markdown).
    /// Use for read-only display mode where Live Preview is not needed.
    func styleAll(_ text: String) -> NSAttributedString {
        return style(text, cursorLocation: -1)
    }

    /// Foldable blocks from the last `style()` call. Available after `style()` returns.
    private(set) var lastFoldableBlocks: [FoldableBlock] = []

    /// Whether the last `style()` call contained at least one Table block.
    private(set) var lastHadTable = false

    /// Style `text`, showing the block containing `cursorLocation` as raw Markdown.
    /// Pass `foldedLines` (1-based line numbers) to collapse those blocks' content.
    func style(_ text: String, cursorLocation: Int, foldedLines: Set<Int> = []) -> NSAttributedString {
        guard !text.isEmpty else {
            lastFoldableBlocks = []
            lastHadTable = false
            return NSAttributedString(string: text)
        }

        lineStartCache = buildLineStarts(in: text)
        defer { lineStartCache = [] }

        let doc = Document(parsing: text)
        lastFoldableBlocks = enumerateFoldableBlocks(from: doc)
        lastHadTable = false
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)

        let cursorRange = findCursorBlock(in: doc, text: text, cursorLocation: cursorLocation)

        // Apply styling per top-level block
        for block in doc.children {
            guard let range = nsRange(for: block, in: text) else { continue }
            if block is Table { lastHadTable = true }

            if isList(block) {
                let ordered = block is OrderedList
                applyListStyle(to: result, block: block, range: range, in: text, ordered: ordered, cursorRange: cursorRange, cursorLocation: cursorLocation)
            } else if let cursor = cursorRange, overlaps(range, cursor) {
                applyRawBlockStyle(for: block, to: result, range: range, in: text, cursorLocation: cursorLocation)
            } else {
                applyBlockStyle(for: block, to: result, range: range, in: text)
            }
        }

        // Overlay fold state on top of normal styling
        if !foldedLines.isEmpty {
            applyFoldState(to: result, doc: doc, text: text, foldedLines: foldedLines)
        }

        return result
    }

    // MARK: - Cursor block detection

    /// Finds the leaf block (or list item) that contains the cursor.
    private func findCursorBlock(in doc: Document, text: String, cursorLocation: Int) -> NSRange? {
        // Collect leaf-level blocks for cursor detection.
        // For lists, use individual ListItems (recursively) instead of the whole list.
        var leafBlocks: [(node: any Markup, range: NSRange)] = []
        for block in doc.children {
            guard let range = nsRange(for: block, in: text) else { continue }
            if isList(block) {
                collectListItems(from: block, in: text, into: &leafBlocks)
            } else {
                leafBlocks.append((block, range))
            }
        }

        // Find the leaf block containing the cursor
        for (_, range) in leafBlocks {
            if range.contains(cursorLocation) || range.location == cursorLocation {
                return range
            }
        }

        // Cursor is right after a block's last character (e.g. end of line).
        // Show that block as raw so the user can keep editing it.
        // But if the character before the cursor is '\n', the cursor is on the next line's
        // start (e.g. an empty line after a list item), so do NOT match the previous block.
        let nsText = text as NSString
        for (_, range) in leafBlocks {
            if range.location + range.length == cursorLocation,
               cursorLocation > 0,
               nsText.substring(with: NSRange(location: cursorLocation - 1, length: 1)) != "\n" {
                return range
            }
        }

        // Cursor is on an empty line between blocks -- render all blocks.
        return nil
    }

    // MARK: - Block-level dispatch

    private func applyRawBlockStyle(for block: any Markup, to storage: NSMutableAttributedString, range: NSRange, in text: String, cursorLocation: Int) {
        applyRawBlockTypeStyle(for: block, to: storage, range: range, in: text)
        // Code blocks and tables handle their own content styling — skip generic inline matching
        if block is CodeBlock || block is Table { return }
        let substring = (text as NSString).substring(with: range)
        applyRawInlinePatterns(to: storage, in: substring, offset: range.location, cursorLocation: cursorLocation)
    }

    private func applyRawBlockTypeStyle(for block: any Markup, to storage: NSMutableAttributedString, range: NSRange, in text: String) {
        switch block {
        case let heading as Heading:
            // "# " prefix -> gray
            let prefix = String(repeating: "#", count: heading.level) + " "
            let prefixLen = (prefix as NSString).length
            if range.length >= prefixLen {
                let prefixRange = NSRange(location: range.location, length: prefixLen)
                storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: prefixRange)
            }
            // Content -> heading font + normal color
            if range.length > prefixLen {
                let contentRange = NSRange(location: range.location + prefixLen, length: range.length - prefixLen)
                storage.addAttributes([
                    .font: boldFont(size: headingFontSize(for: heading.level)),
                    .foregroundColor: colorScheme.textColor
                ], range: contentRange)
            }

        case is CodeBlock:
            // Fence lines (```) -> gray, code body -> green + monospace
            enumerateLines(in: text, range: range) { line, offset, _, _ in
                let lineLen = (line as NSString).length
                guard lineLen > 0 else { return }
                let lineRange = NSRange(location: offset, length: lineLen)
                if line.hasPrefix("```") {
                    storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: lineRange)
                } else {
                    storage.addAttributes([
                        .font: monoFont(size: (baseFontSize * 0.86).rounded()),
                        .foregroundColor: colorScheme.codeColor
                    ], range: lineRange)
                }
            }

        case is BlockQuote:
            // ">" markers -> gray, content stays normal color
            enumerateLines(in: text, range: range) { line, offset, _, _ in
                let lineLen = (line as NSString).length
                if lineLen > 0, line.hasPrefix(">") {
                    let markerLen = line.hasPrefix("> ") ? 2 : 1
                    let markerRange = NSRange(location: offset, length: markerLen)
                    storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: markerRange)
                }
            }

        case is Table:
            applyTableRawStyle(to: storage, range: range, in: text)

        case is ThematicBreak:
            applyRawThematicBreakStyle(to: storage, range: range)

        default:
            break
        }
    }

    private func applyBlockStyle(
        for block: any Markup,
        to storage: NSMutableAttributedString,
        range: NSRange,
        in text: String
    ) {
        switch block {
        case let heading as Heading:
            applyHeadingStyle(level: heading.level, to: storage, range: range)
            hideMarkdownSyntax(in: storage, range: range, text: text, prefix: String(repeating: "#", count: heading.level) + " ")
            applyInlineStyles(to: storage, range: range, in: text, fontSize: headingFontSize(for: heading.level))

        case let codeBlock as CodeBlock:
            applyCodeBlockStyle(to: storage, range: range, text: text, language: codeBlock.language)

        case is BlockQuote:
            applyBlockQuoteStyle(to: storage, range: range, in: text)

        case let table as Table:
            applyTableStyle(to: storage, table: table, range: range, in: text)

        case is ThematicBreak:
            applyThematicBreakStyle(to: storage, range: range)

        default:
            applyInlineStyles(to: storage, range: range, in: text)
        }
    }

    // MARK: - Base attributes

    lazy var baseAttributes: [NSAttributedString.Key: Any] = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        return [
            .font: bodyFont(size: baseFontSize),
            .foregroundColor: colorScheme.textColor,
            .paragraphStyle: paragraphStyle
        ]
    }()
}
