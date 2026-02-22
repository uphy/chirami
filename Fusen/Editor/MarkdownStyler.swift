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

    let noteColor: NoteColor
    let baseFontSize: CGFloat

    static let hiddenAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.clear,
        .font: NSFont.systemFont(ofSize: 0.001)
    ]

    init(noteColor: NoteColor = .yellow, baseFontSize: CGFloat = 14) {
        self.noteColor = noteColor
        self.baseFontSize = baseFontSize
    }

    // MARK: - Public

    /// Style `text`, showing the block containing `cursorLocation` as raw Markdown.
    func style(_ text: String, cursorLocation: Int) -> NSAttributedString {
        guard !text.isEmpty else { return NSAttributedString(string: text) }

        let doc = Document(parsing: text)
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)

        let cursorRange = findCursorBlock(in: doc, text: text, cursorLocation: cursorLocation)

        // Apply styling per top-level block
        for block in doc.children {
            guard let range = nsRange(for: block, in: text) else { continue }

            if isList(block) {
                let ordered = block is OrderedList
                applyListStyle(to: result, block: block, range: range, in: text, ordered: ordered, cursorRange: cursorRange, cursorLocation: cursorLocation)
            } else if let cursor = cursorRange, overlaps(range, cursor) {
                applyRawBlockStyle(for: block, to: result, range: range, in: text)
            } else {
                applyBlockStyle(for: block, to: result, range: range, in: text)
            }
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

    private func applyRawBlockStyle(for block: any Markup, to storage: NSMutableAttributedString, range: NSRange, in text: String) {
        applyRawBlockTypeStyle(for: block, to: storage, range: range, in: text)
        // Code blocks and tables handle their own content styling — skip generic inline matching
        if block is CodeBlock || block is Table { return }
        let substring = (text as NSString).substring(with: range)
        applyRawInlinePatterns(to: storage, in: substring, offset: range.location)
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
                    .font: NSFont.systemFont(ofSize: headingFontSize(for: heading.level), weight: .bold),
                    .foregroundColor: noteColor.textColor
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
                        .font: NSFont.monospacedSystemFont(ofSize: (baseFontSize * 0.86).rounded(), weight: .regular),
                        .foregroundColor: NSColor.systemGreen
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

        case let codeBlock as CodeBlock:
            applyCodeBlockStyle(to: storage, range: range, text: text, language: codeBlock.language)

        case is BlockQuote:
            applyBlockQuoteStyle(to: storage, range: range, in: text)

        case is Table:
            applyTableStyle(to: storage, range: range, in: text)

        default:
            applyInlineStyles(to: storage, range: range, in: text)
        }
    }

    // MARK: - Base attributes

    lazy var baseAttributes: [NSAttributedString.Key: Any] = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        return [
            .font: NSFont.systemFont(ofSize: baseFontSize),
            .foregroundColor: noteColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
    }()
}
