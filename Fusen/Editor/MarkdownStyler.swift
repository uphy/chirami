import AppKit
import Highlightr
import Markdown

extension NSAttributedString.Key {
    /// Marks a character position as a bullet marker to be drawn by BulletLayoutManager.
    static let bulletMarker = NSAttributedString.Key("fusen.bulletMarker")
    /// Marks a character range as a task checkbox. Value: NSNumber (1=checked, 0=unchecked).
    static let taskCheckbox = NSAttributedString.Key("fusen.taskCheckbox")
    /// Nesting level of a list item (0 = top-level). Value: Int.
    static let listNestingLevel = NSAttributedString.Key("fusen.listNestingLevel")
    /// Marks a range as code block background. Drawn by BulletLayoutManager with padding.
    static let codeBlockBackground = NSAttributedString.Key("fusen.codeBlockBackground")
    /// Marks a range as inline code background. Drawn by BulletLayoutManager with rounded corners.
    static let inlineCodeBackground = NSAttributedString.Key("fusen.inlineCodeBackground")
    /// Marks a range as a block quote. Drawn by BulletLayoutManager with a left border.
    static let blockQuoteBorder = NSAttributedString.Key("fusen.blockQuoteBorder")
}

/// Converts a Markdown document into a styled NSAttributedString.
/// Blocks containing the cursor are shown as raw Markdown; others are rendered.
class MarkdownStyler {

    let noteColor: NoteColor
    let baseFontSize: CGFloat

    private static let highlightr: Highlightr? = {
        let h = Highlightr()
        return h
    }()

    private var highlightThemeName: String {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? "github-dark" : "github"
    }

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

        // Collect leaf-level blocks for cursor detection.
        // For lists, use individual ListItems (recursively) instead of the whole list.
        var leafBlocks: [(node: any Markup, range: NSRange)] = []
        for block in doc.children {
            guard let range = nsRange(for: block, in: text) else { continue }
            if block is UnorderedList || block is OrderedList {
                collectListItems(from: block, in: text, into: &leafBlocks)
            } else {
                leafBlocks.append((block, range))
            }
        }

        // Find the leaf block containing the cursor
        var cursorRange: NSRange? = nil
        for (_, range) in leafBlocks {
            if range.contains(cursorLocation) || range.location == cursorLocation {
                cursorRange = range
                break
            }
        }
        if cursorRange == nil {
            // Cursor is right after a block's last character (e.g. end of line).
            // Show that block as raw so the user can keep editing it.
            // But if the character before the cursor is '\n', the cursor is on the next line's
            // start (e.g. an empty line after a list item), so do NOT match the previous block.
            let nsText = text as NSString
            for (_, range) in leafBlocks {
                if range.location + range.length == cursorLocation,
                   cursorLocation > 0,
                   nsText.substring(with: NSRange(location: cursorLocation - 1, length: 1)) != "\n" {
                    cursorRange = range
                    break
                }
            }
            // If still nil, cursor is on an empty line between blocks – render all blocks.
        }

        // Apply styling per top-level block
        for block in doc.children {
            guard let range = nsRange(for: block, in: text) else { continue }

            if block is UnorderedList || block is OrderedList {
                // Style list at item level
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

    // MARK: - Recursive list item collection

    private func collectListItems(from list: any Markup, in text: String, into result: inout [(node: any Markup, range: NSRange)]) {
        for child in list.children {
            guard let item = child as? ListItem, let r = nsRange(for: item, in: text) else { continue }
            var effectiveR = effectiveListItemRange(r, in: text)

            // Trim parent range at the start of the first nested sublist.
            // Child lists have their own entries, so the parent should not cover them.
            for subChild in item.children {
                if (subChild is UnorderedList || subChild is OrderedList),
                   let subRange = nsRange(for: subChild, in: text) {
                    let trimEnd = subRange.location
                    if trimEnd > effectiveR.location && trimEnd < effectiveR.location + effectiveR.length {
                        effectiveR = NSRange(location: effectiveR.location, length: trimEnd - effectiveR.location)
                    }
                    break
                }
            }

            result.append((item, effectiveR))
            for subChild in item.children {
                if subChild is UnorderedList || subChild is OrderedList {
                    collectListItems(from: subChild, in: text, into: &result)
                }
            }
        }
    }

    /// Returns the effective range of a ListItem by trimming lazy continuation lines.
    /// swift-markdown includes lazy continuation lines (lines without leading whitespace)
    /// in a ListItem's range per CommonMark spec, but for the sticky-note UX we want to
    /// exclude them so they are not treated as part of the list item.
    private func effectiveListItemRange(_ range: NSRange, in text: String) -> NSRange {
        let nsText = text as NSString
        let substring = nsText.substring(with: range)
        let lines = substring.components(separatedBy: "\n")

        // Always include the first line (the marker line)
        var includedLength = (lines[0] as NSString).length

        for i in 1..<lines.count {
            let line = lines[i]
            // Empty line or line not starting with whitespace → stop
            if line.isEmpty || (!line.hasPrefix(" ") && !line.hasPrefix("\t")) {
                break
            }
            // +1 for the newline separator before this line
            includedLength += 1 + (line as NSString).length
        }

        // Include trailing newline if present in the original range
        let afterIncluded = includedLength + 1 // position of potential trailing \n
        if afterIncluded <= range.length {
            let charAtEnd = nsText.substring(with: NSRange(location: range.location + includedLength, length: 1))
            if charAtEnd == "\n" {
                includedLength += 1
            }
        }

        return NSRange(location: range.location, length: includedLength)
    }

    // MARK: - Block styling

    private func overlaps(_ a: NSRange, _ b: NSRange) -> Bool {
        NSIntersectionRange(a, b).length > 0 || a.contains(b.location)
    }

    private func applyRawBlockStyle(for block: any Markup, to storage: NSMutableAttributedString, range: NSRange, in text: String) {
        // Block-type-specific styling (headings, code blocks, block quotes)
        applyRawBlockTypeStyle(for: block, to: storage, range: range, in: text)
        // Code blocks contain literal text – skip inline pattern matching
        if block is CodeBlock { return }
        let substring = (text as NSString).substring(with: range)
        // Inline markers → gray, content → styled
        applyRawInlinePatterns(to: storage, in: substring, offset: range.location)
    }

    private func applyRawBlockTypeStyle(for block: any Markup, to storage: NSMutableAttributedString, range: NSRange, in text: String) {
        switch block {
        case let heading as Heading:
            // "# " prefix → gray
            let prefix = String(repeating: "#", count: heading.level) + " "
            let prefixLen = (prefix as NSString).length
            if range.length >= prefixLen {
                let prefixRange = NSRange(location: range.location, length: prefixLen)
                storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: prefixRange)
            }
            // Content → heading font + normal color
            if range.length > prefixLen {
                let contentRange = NSRange(location: range.location + prefixLen, length: range.length - prefixLen)
                let headingSize: CGFloat
                switch heading.level {
                case 1: headingSize = (baseFontSize * 1.7).rounded()
                case 2: headingSize = (baseFontSize * 1.43).rounded()
                case 3: headingSize = (baseFontSize * 1.21).rounded()
                default: headingSize = (baseFontSize * 1.07).rounded()
                }
                storage.addAttributes([
                    .font: NSFont.systemFont(ofSize: headingSize, weight: .bold),
                    .foregroundColor: noteColor.textColor
                ], range: contentRange)
            }

        case is CodeBlock:
            // Fence lines (```) → gray, code body → green + monospace
            let substring = (text as NSString).substring(with: range)
            let lines = substring.components(separatedBy: "\n")
            var currentOffset = range.location
            for line in lines {
                let lineLen = (line as NSString).length
                if lineLen > 0 {
                    let lineRange = NSRange(location: currentOffset, length: lineLen)
                    if line.hasPrefix("```") {
                        storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: lineRange)
                    } else {
                        storage.addAttributes([
                            .font: NSFont.monospacedSystemFont(ofSize: (baseFontSize * 0.86).rounded(), weight: .regular),
                            .foregroundColor: NSColor.systemGreen
                        ], range: lineRange)
                    }
                }
                currentOffset += lineLen + 1 // +1 for newline
            }

        case is BlockQuote:
            // ">" markers → gray, content stays normal color
            let substring = (text as NSString).substring(with: range)
            let lines = substring.components(separatedBy: "\n")
            var currentOffset = range.location
            for line in lines {
                let lineLen = (line as NSString).length
                if lineLen > 0, line.hasPrefix(">") {
                    let markerLen = line.hasPrefix("> ") ? 2 : 1
                    let markerRange = NSRange(location: currentOffset, length: markerLen)
                    storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: markerRange)
                }
                currentOffset += lineLen + 1
            }

        default:
            // Paragraph – base attributes are already applied
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

        default:
            // Paragraph – apply inline styles
            applyInlineStyles(to: storage, range: range, in: text)
        }
    }

    // MARK: - Heading

    private func applyHeadingStyle(level: Int, to storage: NSMutableAttributedString, range: NSRange) {
        let headingSize: CGFloat
        switch level {
        case 1: headingSize = (baseFontSize * 1.7).rounded()
        case 2: headingSize = (baseFontSize * 1.43).rounded()
        case 3: headingSize = (baseFontSize * 1.21).rounded()
        default: headingSize = (baseFontSize * 1.07).rounded()
        }
        let font = NSFont.systemFont(ofSize: headingSize, weight: .bold)
        storage.addAttributes([
            .font: font,
            .foregroundColor: noteColor.textColor
        ], range: range)
    }

    // MARK: - Code block

    static let codeBlockVerticalPadding: CGFloat = 6

    private func applyCodeBlockStyle(to storage: NSMutableAttributedString, range: NSRange, text: String, language: String? = nil) {
        let horizontalPadding: CGFloat = 8
        let verticalPadding = Self.codeBlockVerticalPadding

        // Mark entire range for custom background drawing by BulletLayoutManager
        storage.addAttributes([
            .codeBlockBackground: NSColor.labelColor.withAlphaComponent(0.08)
        ], range: range)

        let nsText = text as NSString
        let substring = nsText.substring(with: range)
        let lines = substring.components(separatedBy: "\n")

        let monoFont = NSFont.monospacedSystemFont(ofSize: (baseFontSize * 0.86).rounded(), weight: .regular)

        // Collect code body lines (excluding fence lines) for syntax highlighting
        struct CodeLine {
            let text: String
            let offset: Int
            let length: Int
        }
        var codeLines: [CodeLine] = []
        var tempOffset = range.location
        for line in lines {
            let lineLen = (line as NSString).length
            if !line.hasPrefix("```") {
                codeLines.append(CodeLine(text: line, offset: tempOffset, length: lineLen))
            }
            tempOffset += lineLen + 1
        }

        // Attempt syntax highlighting with Highlightr
        var highlightColors: [(offset: Int, length: Int, color: NSColor)]? = nil
        if let lang = language, !lang.isEmpty, !codeLines.isEmpty {
            let codeBody = codeLines.map(\.text).joined(separator: "\n")
            if let highlightr = Self.highlightr {
                highlightr.setTheme(to: highlightThemeName)
                if let highlighted = highlightr.highlight(codeBody, as: lang, fastRender: false) {
                    // Extract foreground colors from Highlightr output and map to storage positions
                    var colors: [(offset: Int, length: Int, color: NSColor)] = []
                    let fullRange = NSRange(location: 0, length: highlighted.length)
                    // Track position within highlighted string, mapping to code lines
                    var hlOffset = 0
                    for (lineIdx, codeLine) in codeLines.enumerated() {
                        let lineStartInHighlighted = hlOffset
                        let lineLen = (codeLine.text as NSString).length
                        // Enumerate foreground color attributes in this line's range within highlighted string
                        let hlLineRange = NSRange(location: lineStartInHighlighted, length: lineLen)
                        if NSIntersectionRange(hlLineRange, fullRange).length > 0 {
                            highlighted.enumerateAttribute(.foregroundColor, in: hlLineRange) { value, attrRange, _ in
                                if let color = value as? NSColor {
                                    let storageOffset = codeLine.offset + (attrRange.location - lineStartInHighlighted)
                                    colors.append((offset: storageOffset, length: attrRange.length, color: color))
                                }
                            }
                        }
                        hlOffset += lineLen + (lineIdx < codeLines.count - 1 ? 1 : 0) // +1 for \n separator
                    }
                    if !colors.isEmpty {
                        highlightColors = colors
                    }
                }
            }
        }

        var currentOffset = range.location
        for (i, line) in lines.enumerated() {
            let lineLen = (line as NSString).length
            let isFirstLine = (i == 0)
            let isLastLine = (i == lines.count - 1)

            // Build per-line paragraph style (first/last lines get vertical padding)
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.headIndent = horizontalPadding
            paraStyle.firstLineHeadIndent = horizontalPadding
            paraStyle.tailIndent = -horizontalPadding
            if isFirstLine {
                paraStyle.paragraphSpacingBefore = verticalPadding
            }
            if isLastLine {
                paraStyle.paragraphSpacing = verticalPadding
            }

            // Apply paragraph style to the line (including its trailing newline)
            let fullLineLen = isLastLine ? lineLen : lineLen + 1
            if fullLineLen > 0 {
                let lineRange = NSRange(location: currentOffset, length: fullLineLen)
                storage.addAttributes([.paragraphStyle: paraStyle], range: lineRange)
            }

            if line.hasPrefix("```") {
                // Hide fence line text
                if lineLen > 0 {
                    let lineRange = NSRange(location: currentOffset, length: lineLen)
                    storage.addAttributes(hiddenAttributes, range: lineRange)
                }
                // Hide the newline after the fence line to collapse the line height
                if !isLastLine {
                    let nlRange = NSRange(location: currentOffset + lineLen, length: 1)
                    storage.addAttributes(hiddenAttributes, range: nlRange)
                }
            } else {
                // Code body line: apply monospace font
                if lineLen > 0 {
                    let lineRange = NSRange(location: currentOffset, length: lineLen)
                    storage.addAttributes([.font: monoFont], range: lineRange)
                    if highlightColors == nil {
                        // No syntax highlighting available: fallback to green
                        storage.addAttributes([.foregroundColor: NSColor.systemGreen], range: lineRange)
                    }
                }
            }
            currentOffset += lineLen + (isLastLine ? 0 : 1) // +1 for newline separator
        }

        // Apply syntax highlight colors on top
        if let colors = highlightColors {
            for entry in colors {
                let colorRange = NSRange(location: entry.offset, length: entry.length)
                storage.addAttributes([.foregroundColor: entry.color], range: colorRange)
            }
        }
    }

    // MARK: - Block quote

    static let blockQuoteLeftPadding: CGFloat = 16

    private func applyBlockQuoteStyle(to storage: NSMutableAttributedString, range: NSRange, in text: String) {
        let nsText = text as NSString
        let substring = nsText.substring(with: range)
        let lines = substring.components(separatedBy: "\n")

        let indent = Self.blockQuoteLeftPadding

        // Mark entire range for left border drawing by BulletLayoutManager
        storage.addAttributes([
            .blockQuoteBorder: noteColor.textColor.withAlphaComponent(0.25),
            .foregroundColor: NSColor.secondaryLabelColor
        ], range: range)

        var currentOffset = range.location
        for (i, line) in lines.enumerated() {
            let lineLen = (line as NSString).length
            let isLastLine = (i == lines.count - 1)
            let fullLineLen = isLastLine ? lineLen : lineLen + 1

            // Paragraph style with indent
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.headIndent = indent
            paraStyle.firstLineHeadIndent = indent
            paraStyle.lineSpacing = 6
            if fullLineLen > 0 {
                let lineRange = NSRange(location: currentOffset, length: fullLineLen)
                storage.addAttributes([.paragraphStyle: paraStyle], range: lineRange)
            }

            // Hide "> " or ">" prefix
            if lineLen > 0, line.hasPrefix(">") {
                let markerLen = line.hasPrefix("> ") ? 2 : 1
                let markerRange = NSRange(location: currentOffset, length: markerLen)
                storage.addAttributes(hiddenAttributes, range: markerRange)

                // Apply inline styles to content after the marker
                let contentStart = markerLen
                if lineLen > contentStart {
                    let contentRange = NSRange(location: currentOffset + contentStart, length: lineLen - contentStart)
                    let contentText = nsText.substring(with: contentRange)
                    applyInlinePatterns(to: storage, in: contentText, offset: contentRange.location)
                }
            }

            currentOffset += lineLen + (isLastLine ? 0 : 1)
        }
    }

    // MARK: - List

    private func applyListStyle(
        to storage: NSMutableAttributedString,
        block: any Markup,
        range: NSRange,
        in text: String,
        ordered: Bool,
        cursorRange: NSRange?,
        cursorLocation: Int,
        nestingLevel: Int = 0
    ) {
        for child in block.children {
            guard let item = child as? ListItem,
                  let rawItemRange = nsRange(for: item, in: text) else { continue }
            let itemRange = effectiveListItemRange(rawItemRange, in: text)

            let itemText = (text as NSString).substring(with: itemRange)

            // Count and hide leading whitespace (indentation from nesting)
            let leadingWhitespace = itemText.prefix(while: { $0 == "\t" || $0 == " " })
            let leadingWSLength = (leadingWhitespace as NSString).length

            // The text after leading whitespace
            let strippedText = String(itemText.dropFirst(leadingWhitespace.count))

            // Detect marker length (e.g. "- ", "* ", "1. ")
            let markerLength: Int
            if ordered {
                if let match = strippedText.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                    markerLength = strippedText.distance(from: strippedText.startIndex, to: match.upperBound)
                } else { continue }
            } else {
                if strippedText.hasPrefix("- ") || strippedText.hasPrefix("* ") {
                    markerLength = 2
                } else { continue }
            }

            // Check for task checkbox
            let isChecked: Bool?
            if let checkbox = item.checkbox {
                isChecked = (checkbox == .checked)
            } else {
                isChecked = nil
            }

            // Content starts after leading whitespace + marker; for checkboxes, also skip "[ ] " or "[x] " (4 chars)
            let checkboxSyntaxLength = isChecked != nil ? 4 : 0
            let contentStart = leadingWSLength + markerLength + checkboxSyntaxLength

            // Absolute position of the marker (after leading whitespace)
            let markerAbsLocation = itemRange.location + leadingWSLength

            // Use own content range (excluding nested sublists) for cursor overlap check.
            var ownContentEnd = itemRange.location + itemRange.length
            for subChild in item.children {
                if (subChild is UnorderedList || subChild is OrderedList),
                   let subRange = nsRange(for: subChild, in: text) {
                    ownContentEnd = min(ownContentEnd, subRange.location)
                    break
                }
            }
            let ownRange = NSRange(location: itemRange.location, length: max(0, ownContentEnd - itemRange.location))
            let editing = cursorRange.map { overlaps(ownRange, $0) } ?? false

            if editing && (isChecked == nil || cursorLocation < itemRange.location + contentStart) {
                // Gray only the marker (leading whitespace + marker + optional checkbox syntax)
                let markerEnd = min(contentStart, itemRange.length)
                if markerEnd > 0 {
                    let markerRange = NSRange(location: itemRange.location, length: markerEnd)
                    storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: markerRange)
                }
                // Apply inline styles to content
                if itemRange.length > contentStart {
                    let contentRange = NSRange(location: itemRange.location + contentStart, length: itemRange.length - contentStart)
                    let contentText = (text as NSString).substring(with: contentRange)
                    applyRawInlinePatterns(to: storage, in: contentText, offset: contentRange.location)
                }
            } else if editing {
                // Task item with cursor in body zone

                // Hide leading whitespace for nested items
                if leadingWSLength > 0 {
                    let wsRange = NSRange(location: itemRange.location, length: leadingWSLength)
                    storage.addAttributes(hiddenAttributes, range: wsRange)
                }

                // Apply paragraph style for indent
                applyListParagraphStyle(to: storage, itemRange: itemRange, ordered: ordered, nestingLevel: nestingLevel, isTask: true, in: text)

                // Render the prefix (marker + checkbox)
                if !ordered {
                    applyTaskPrefixRendered(to: storage, itemRange: itemRange, markerAbsLocation: markerAbsLocation, markerLength: markerLength, isChecked: isChecked!, nestingLevel: nestingLevel)
                }

                // Body: keep baseAttributes (already applied), apply inline styles
                if itemRange.length > contentStart {
                    let contentRange = NSRange(location: itemRange.location + contentStart, length: itemRange.length - contentStart)
                    let contentText = (text as NSString).substring(with: contentRange)
                    applyInlinePatterns(to: storage, in: contentText, offset: contentRange.location)
                }
            } else {
                // Not editing: fully rendered

                // Hide leading whitespace for nested items
                if leadingWSLength > 0 {
                    let wsRange = NSRange(location: itemRange.location, length: leadingWSLength)
                    storage.addAttributes(hiddenAttributes, range: wsRange)
                }

                if ordered {
                    let markerRange = NSRange(location: markerAbsLocation, length: markerLength)
                    storage.addAttributes([
                        .foregroundColor: NSColor.secondaryLabelColor
                    ], range: markerRange)
                } else if let checked = isChecked {
                    applyTaskPrefixRendered(to: storage, itemRange: itemRange, markerAbsLocation: markerAbsLocation, markerLength: markerLength, isChecked: checked, nestingLevel: nestingLevel)
                } else {
                    // Unordered bullet (no checkbox)
                    let charRange = NSRange(location: markerAbsLocation, length: 1)
                    storage.addAttributes([
                        .foregroundColor: NSColor.clear,
                        .font: NSFont.systemFont(ofSize: 0.001),
                        .bulletMarker: true,
                        .listNestingLevel: nestingLevel
                    ], range: charRange)
                    if markerLength > 1 {
                        let spaceRange = NSRange(location: markerAbsLocation + 1, length: markerLength - 1)
                        storage.addAttributes(hiddenAttributes, range: spaceRange)
                    }
                }

                // Task checkbox content styling (strikethrough for checked)
                if let checked = isChecked, checked, itemRange.length > contentStart {
                    let contentRange = NSRange(location: itemRange.location + contentStart, length: itemRange.length - contentStart)
                    storage.addAttributes([
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: NSColor.tertiaryLabelColor
                    ], range: contentRange)
                }

                // Paragraph style
                applyListParagraphStyle(to: storage, itemRange: itemRange, ordered: ordered, nestingLevel: nestingLevel, isTask: isChecked != nil, in: text)

                // Inline styles on content
                if itemRange.length > contentStart {
                    let contentRange = NSRange(location: itemRange.location + contentStart, length: itemRange.length - contentStart)
                    let contentText = (text as NSString).substring(with: contentRange)
                    applyInlinePatterns(to: storage, in: contentText, offset: contentRange.location)
                }

            }

            // Recurse into nested lists within this item
            for subChild in item.children {
                if let subList = subChild as? UnorderedList {
                    if let subRange = nsRange(for: subList, in: text) {
                        applyListStyle(to: storage, block: subList, range: subRange, in: text, ordered: false, cursorRange: cursorRange, cursorLocation: cursorLocation, nestingLevel: nestingLevel + 1)
                    }
                } else if let subList = subChild as? OrderedList {
                    if let subRange = nsRange(for: subList, in: text) {
                        applyListStyle(to: storage, block: subList, range: subRange, in: text, ordered: true, cursorRange: cursorRange, cursorLocation: cursorLocation, nestingLevel: nestingLevel + 1)
                    }
                }
            }
        }
    }

    /// Renders the marker + checkbox prefix of a task list item as a hidden checkbox glyph.
    private func applyTaskPrefixRendered(
        to storage: NSMutableAttributedString,
        itemRange: NSRange,
        markerAbsLocation: Int,
        markerLength: Int,
        isChecked: Bool,
        nestingLevel: Int = 0
    ) {
        // Marker character (e.g. "-"): hide and tag as checkbox
        let charRange = NSRange(location: markerAbsLocation, length: 1)
        storage.addAttributes([
            .foregroundColor: NSColor.clear,
            .font: NSFont.systemFont(ofSize: 0.001),
            .taskCheckbox: NSNumber(value: isChecked ? 1 : 0),
            .listNestingLevel: nestingLevel
        ], range: charRange)

        // Space after marker: hide
        if markerLength > 1 {
            let spaceRange = NSRange(location: markerAbsLocation + 1, length: markerLength - 1)
            storage.addAttributes(hiddenAttributes, range: spaceRange)
        }

        // Checkbox syntax "[ ]" or "[x]": hide and tag
        let checkboxCharRange = NSRange(location: markerAbsLocation + markerLength, length: 3)
        storage.addAttributes([
            .foregroundColor: NSColor.clear,
            .font: NSFont.systemFont(ofSize: 0.001),
            .taskCheckbox: NSNumber(value: isChecked ? 1 : 0),
            .listNestingLevel: nestingLevel
        ], range: checkboxCharRange)

        // Space after checkbox: hide
        let spaceAfterCheckbox = NSRange(location: markerAbsLocation + markerLength + 3, length: 1)
        storage.addAttributes(hiddenAttributes, range: spaceAfterCheckbox)
    }

    /// Applies paragraph style (indent, line spacing) for a list item.
    private func applyListParagraphStyle(
        to storage: NSMutableAttributedString,
        itemRange: NSRange,
        ordered: Bool,
        nestingLevel: Int = 0,
        isTask: Bool = false,
        in text: String
    ) {
        let nestingStep: CGFloat = 20
        let textStart: CGFloat = (ordered || isTask) ? 20 : 14
        let levelIndent = textStart + nestingStep * CGFloat(nestingLevel)

        let font = NSFont.systemFont(ofSize: baseFontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = 1
        paragraphStyle.lineSpacing = 6
        paragraphStyle.minimumLineHeight = ceil(font.ascender - font.descender + font.leading)
        paragraphStyle.headIndent = levelIndent
        if ordered {
            paragraphStyle.firstLineHeadIndent = nestingStep * CGFloat(nestingLevel)
            paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: levelIndent)]
        } else {
            paragraphStyle.firstLineHeadIndent = levelIndent
        }

        // Apply paragraph style to the full line range so leading whitespace inherits the style
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: itemRange)
        storage.addAttributes([.paragraphStyle: paragraphStyle], range: lineRange)
    }

    // MARK: - Inline styles

    private func applyInlineStyles(to storage: NSMutableAttributedString, range: NSRange, in text: String) {
        let substring = (text as NSString).substring(with: range)
        applyInlinePatterns(to: storage, in: substring, offset: range.location)
    }

    private func applyInlinePatterns(to storage: NSMutableAttributedString, in text: String, offset: Int) {
        // Bold: **text** or __text__
        applyPattern(
            #"\*\*(.+?)\*\*|__(.+?)__"#,
            to: storage,
            in: text,
            offset: offset,
            attributes: [.font: NSFont.systemFont(ofSize: baseFontSize, weight: .bold)],
            hideMarkers: true,
            markerLength: 2
        )

        // Italic: *text* or _text_
        applyPattern(
            #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#,
            to: storage,
            in: text,
            offset: offset,
            attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: baseFontSize), toHaveTrait: .italicFontMask)],
            hideMarkers: true,
            markerLength: 1
        )

        // Strikethrough: ~~text~~
        applyPattern(
            #"~~(.+?)~~"#,
            to: storage,
            in: text,
            offset: offset,
            attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue],
            hideMarkers: true,
            markerLength: 2
        )

        // Inline code: `code`
        applyPattern(
            #"`(.+?)`"#,
            to: storage,
            in: text,
            offset: offset,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: baseFontSize - 1, weight: .regular),
                .foregroundColor: NSColor.systemOrange,
                .inlineCodeBackground: NSColor.labelColor.withAlphaComponent(0.08)
            ],
            hideMarkers: true,
            markerLength: 1
        )

        // Link: [text](url)
        applyLinkPattern(to: storage, in: text, offset: offset)
    }

    private func applyRawInlinePatterns(to storage: NSMutableAttributedString, in text: String, offset: Int) {
        // Bold: **text** or __text__
        applyRawPattern(
            #"\*\*(.+?)\*\*|__(.+?)__"#,
            to: storage,
            in: text,
            offset: offset,
            contentAttributes: [
                .font: NSFont.systemFont(ofSize: baseFontSize, weight: .bold),
                .foregroundColor: noteColor.textColor
            ]
        )

        // Italic: *text* or _text_
        applyRawPattern(
            #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#,
            to: storage,
            in: text,
            offset: offset,
            contentAttributes: [
                .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: baseFontSize), toHaveTrait: .italicFontMask),
                .foregroundColor: noteColor.textColor
            ]
        )

        // Strikethrough: ~~text~~
        applyRawPattern(
            #"~~(.+?)~~"#,
            to: storage,
            in: text,
            offset: offset,
            contentAttributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: noteColor.textColor
            ]
        )

        // Inline code: `code`
        applyRawPattern(
            #"`(.+?)`"#,
            to: storage,
            in: text,
            offset: offset,
            contentAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: baseFontSize - 1, weight: .regular),
                .foregroundColor: NSColor.systemOrange,
                .inlineCodeBackground: NSColor.labelColor.withAlphaComponent(0.08)
            ]
        )

        // Link: [text](url)
        applyRawLinkPattern(to: storage, in: text, offset: offset)
    }

    private func applyRawPattern(
        _ pattern: String,
        to storage: NSMutableAttributedString,
        in text: String,
        offset: Int,
        contentAttributes: [NSAttributedString.Key: Any],
        markerColor: NSColor = .secondaryLabelColor
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)

            // Find the first non-empty capture group (content without markers)
            var contentAdjustedRange: NSRange? = nil
            for groupIdx in 1..<match.numberOfRanges {
                let contentRange = match.range(at: groupIdx)
                if contentRange.location != NSNotFound {
                    contentAdjustedRange = NSRange(location: contentRange.location + offset, length: contentRange.length)
                    break
                }
            }

            if let contentRange = contentAdjustedRange {
                // Gray the opening marker (before content)
                let openLen = contentRange.location - fullRange.location
                if openLen > 0 {
                    let openRange = NSRange(location: fullRange.location, length: openLen)
                    storage.addAttributes([.foregroundColor: markerColor], range: openRange)
                }
                // Gray the closing marker (after content)
                let closeStart = contentRange.location + contentRange.length
                let closeLen = (fullRange.location + fullRange.length) - closeStart
                if closeLen > 0 {
                    let closeRange = NSRange(location: closeStart, length: closeLen)
                    storage.addAttributes([.foregroundColor: markerColor], range: closeRange)
                }
                // Apply content attributes
                storage.addAttributes(contentAttributes, range: contentRange)
            } else {
                // No capture group found – gray entire match
                storage.addAttributes([.foregroundColor: markerColor], range: fullRange)
            }
        }
    }

    private func applyRawLinkPattern(to storage: NSMutableAttributedString, in text: String, offset: Int) {
        guard let regex = try? NSRegularExpression(pattern: #"\[(.+?)\]\((.+?)\)"#) else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            // Full match → gray (all markers)
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: fullRange)

            // Link text (group 1) → link color
            let textRange = match.range(at: 1)
            if textRange.location != NSNotFound {
                let adjustedRange = NSRange(location: textRange.location + offset, length: textRange.length)
                storage.addAttributes([.foregroundColor: noteColor.linkColor], range: adjustedRange)
            }
        }
    }

    private func applyPattern(
        _ pattern: String,
        to storage: NSMutableAttributedString,
        in text: String,
        offset: Int,
        attributes: [NSAttributedString.Key: Any],
        hideMarkers: Bool,
        markerLength: Int
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            storage.addAttributes(attributes, range: fullRange)

            if hideMarkers {
                // Hide opening marker
                let openRange = NSRange(location: fullRange.location, length: markerLength)
                storage.addAttributes(hiddenAttributes, range: openRange)

                // Hide closing marker
                let closeRange = NSRange(location: fullRange.location + fullRange.length - markerLength, length: markerLength)
                storage.addAttributes(hiddenAttributes, range: closeRange)
            }
        }
    }

    private func applyLinkPattern(to storage: NSMutableAttributedString, in text: String, offset: Int) {
        guard let regex = try? NSRegularExpression(pattern: #"\[(.+?)\]\((.+?)\)"#) else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            let urlRange = match.range(at: 2)
            if urlRange.location != NSNotFound {
                let urlStr = nsText.substring(with: urlRange)
                if let url = URL(string: urlStr) {
                    storage.addAttributes([
                        .link: url,
                        .foregroundColor: noteColor.linkColor
                    ], range: fullRange)
                }
            }

            // Hide the markdown syntax for the link wrapper: [, ](url)
            // Show only the link text
            let textRange = match.range(at: 1)
            if textRange.location != NSNotFound {
                // Hide "[" before text
                let openBracket = NSRange(location: fullRange.location, length: 1)
                storage.addAttributes(hiddenAttributes, range: openBracket)

                // Hide "](url)" after text
                let afterText = NSRange(
                    location: fullRange.location + 1 + textRange.length,
                    length: fullRange.length - 1 - textRange.length
                )
                storage.addAttributes(hiddenAttributes, range: afterText)
            }
        }
    }

    // MARK: - Markdown syntax hiding

    private func hideMarkdownSyntax(
        in storage: NSMutableAttributedString,
        range: NSRange,
        text: String,
        prefix: String
    ) {
        let prefixLen = prefix.count
        guard range.length > prefixLen else { return }
        let prefixRange = NSRange(location: range.location, length: prefixLen)
        storage.addAttributes(hiddenAttributes, range: prefixRange)
    }

    // MARK: - Source range → NSRange

    /// Converts a swift-markdown source location to NSRange (UTF-16 units).
    /// swift-markdown columns are 1-based UTF-8 byte offsets; NSRange uses UTF-16.
    func nsRange(for node: any Markup, in text: String) -> NSRange? {
        guard let sourceRange = node.range else { return nil }
        guard let startIdx = stringIndex(line: sourceRange.lowerBound.line,
                                         utf8Column: sourceRange.lowerBound.column,
                                         in: text),
              let endIdx = stringIndex(line: sourceRange.upperBound.line,
                                       utf8Column: sourceRange.upperBound.column,
                                       in: text),
              startIdx <= endIdx else { return nil }
        return NSRange(startIdx..<endIdx, in: text)
    }

    /// Returns the `String.Index` for a given 1-based line and 1-based UTF-8 byte column.
    private func stringIndex(line: Int, utf8Column: Int, in text: String) -> String.Index? {
        var lineStart = text.startIndex
        for _ in 1..<line {
            guard let nl = text[lineStart...].firstIndex(of: "\n") else { return nil }
            lineStart = text.index(after: nl)
        }
        let byteOffset = utf8Column - 1
        return text.utf8.index(lineStart, offsetBy: byteOffset, limitedBy: text.utf8.endIndex)
    }

    // MARK: - Attributes

    var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        return [
            .font: NSFont.systemFont(ofSize: baseFontSize),
            .foregroundColor: noteColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private var hiddenAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.clear,
            .font: NSFont.systemFont(ofSize: 0.001)
        ]
    }
}

private extension NSRange {
    func contains(_ location: Int) -> Bool {
        location >= self.location && location < self.location + self.length
    }
}
