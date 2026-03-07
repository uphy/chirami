import AppKit
import Markdown

// MARK: - List and task list styling

extension MarkdownStyler {

    // MARK: - Recursive list item collection

    func collectListItems(from list: any Markup, in text: String, into result: inout [(node: any Markup, range: NSRange)]) {
        let nsText = text as NSString
        for child in list.children {
            guard let item = child as? ListItem, let r = nsRange(for: item, in: text) else { continue }
            var effectiveR = effectiveListItemRange(r, in: text)

            // Extend range to include leading whitespace on the item's line.
            // swift-markdown may report the ListItem range starting at the marker,
            // but the indentation before the marker belongs to this item visually.
            let lineStart = nsText.lineRange(for: NSRange(location: effectiveR.location, length: 0)).location
            if lineStart < effectiveR.location {
                let ext = effectiveR.location - lineStart
                effectiveR = NSRange(location: lineStart, length: effectiveR.length + ext)
            }

            // Trim parent range at the LINE START of the first nested sublist.
            // Using line start (not AST start) ensures the child's leading
            // indentation is excluded from the parent's range.
            for subChild in item.children {
                if isList(subChild),
                   let subRange = nsRange(for: subChild, in: text) {
                    let trimEnd = nsText.lineRange(for: NSRange(location: subRange.location, length: 0)).location
                    if trimEnd > effectiveR.location && trimEnd < effectiveR.location + effectiveR.length {
                        effectiveR = NSRange(location: effectiveR.location, length: trimEnd - effectiveR.location)
                    }
                    break
                }
            }

            result.append((item, effectiveR))
            for subChild in item.children where isList(subChild) {
                collectListItems(from: subChild, in: text, into: &result)
            }
        }
    }

    /// Returns the effective range of a ListItem by trimming lazy continuation lines.
    /// swift-markdown includes lazy continuation lines (lines without leading whitespace)
    /// in a ListItem's range per CommonMark spec, but for the sticky-note UX we want to
    /// exclude them so they are not treated as part of the list item.
    func effectiveListItemRange(_ range: NSRange, in text: String) -> NSRange {
        let nsText = text as NSString

        // swift-markdown may report a very short range for empty list items
        // (no content after the marker). Extend to cover the item's first line
        // so the marker text can always be detected.
        var range = range
        let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
        let lineContent = nsText.substring(with: lineRange)
        let lineContentEnd = lineRange.location + lineRange.length
            - (lineContent.hasSuffix("\n") ? 1 : 0)
        let minLength = max(0, lineContentEnd - range.location)
        if range.length < minLength {
            range = NSRange(location: range.location, length: minLength)
        }

        let substring = nsText.substring(with: range)
        let lines = substring.components(separatedBy: "\n")

        // Always include the first line (the marker line)
        var includedLength = (lines[0] as NSString).length

        for i in 1..<lines.count {
            let line = lines[i]
            // Empty line or line not starting with whitespace -> stop
            if line.isEmpty || (!line.hasPrefix(" ") && !line.hasPrefix("\t")) {
                break
            }
            // +1 for the newline separator before this line
            includedLength += 1 + (line as NSString).length
        }

        // Include trailing newline if present in the original range
        let afterIncluded = includedLength + 1
        if afterIncluded <= range.length {
            let charAtEnd = nsText.substring(with: NSRange(location: range.location + includedLength, length: 1))
            if charAtEnd == "\n" {
                includedLength += 1
            }
        }

        return NSRange(location: range.location, length: includedLength)
    }

    // MARK: - List style application

    func applyListStyle(
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
                if isList(subChild),
                   let subRange = nsRange(for: subChild, in: text) {
                    let nsText = text as NSString
                    let lineStart = nsText.lineRange(for: NSRange(location: subRange.location, length: 0)).location
                    ownContentEnd = min(ownContentEnd, lineStart)
                    break
                }
            }
            let ownRange = NSRange(location: itemRange.location, length: max(0, ownContentEnd - itemRange.location))
            let editing = cursorRange.map { overlaps(ownRange, $0) } ?? false

            // Raw style applies whenever the cursor is in the prefix region, including empty
            // items: hidden marker chars + firstLineHeadIndent would shift the cursor visually.
            let cursorInPrefix = editing && cursorLocation < itemRange.location + contentStart
            if cursorInPrefix {
                applyListItemRawStyle(
                    to: storage, itemRange: itemRange, contentStart: contentStart,
                    ownContentEnd: ownContentEnd,
                    cursorLocation: isChecked != nil ? cursorLocation : nil,
                    in: text
                )
            } else if editing, let checked = isChecked {
                applyListItemEditingTaskStyle(
                    to: storage, itemRange: itemRange, markerAbsLocation: markerAbsLocation,
                    markerLength: markerLength, isChecked: checked, contentStart: contentStart,
                    ordered: ordered, nestingLevel: nestingLevel,
                    ownContentEnd: ownContentEnd, cursorLocation: cursorLocation,
                    in: text
                )
            } else if editing {
                applyListItemEditingBodyStyle(
                    to: storage, itemRange: itemRange, markerAbsLocation: markerAbsLocation,
                    markerLength: markerLength, contentStart: contentStart,
                    ordered: ordered, nestingLevel: nestingLevel,
                    ownContentEnd: ownContentEnd, cursorLocation: cursorLocation,
                    in: text
                )
            } else {
                applyListItemRenderedStyle(
                    to: storage, itemRange: itemRange, markerAbsLocation: markerAbsLocation,
                    markerLength: markerLength, isChecked: isChecked, contentStart: contentStart,
                    ordered: ordered, nestingLevel: nestingLevel,
                    ownContentEnd: ownContentEnd,
                    in: text
                )
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

    // MARK: - List item style variants

    /// Raw editing style: shows marker as gray, content with raw inline patterns.
    private func applyListItemRawStyle(
        to storage: NSMutableAttributedString,
        itemRange: NSRange,
        contentStart: Int,
        ownContentEnd: Int,
        cursorLocation: Int? = nil,
        in text: String
    ) {
        // Restore a visible tab interval for raw mode.
        // Rendered siblings may have set defaultTabInterval=0.001 on the shared line range,
        // making tab characters invisible. Override with the nesting step so tabs are visible.
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: itemRange)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.defaultTabInterval = 20
        storage.addAttributes([.paragraphStyle: paragraphStyle], range: lineRange)

        // Gray only the marker (leading whitespace + marker + optional checkbox syntax)
        let markerEnd = min(contentStart, itemRange.length)
        if markerEnd > 0 {
            let markerRange = NSRange(location: itemRange.location, length: markerEnd)
            storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: markerRange)
        }
        // Apply inline styles to own content (exclude nested sublists)
        let ownLength = ownContentEnd - itemRange.location
        if ownLength > contentStart {
            let contentRange = NSRange(location: itemRange.location + contentStart, length: ownLength - contentStart)
            let contentText = (text as NSString).substring(with: contentRange)
            applyRawInlinePatterns(to: storage, in: contentText, offset: contentRange.location, cursorLocation: cursorLocation)
        }
    }

    /// Editing task item with cursor in body zone: render prefix as checkbox, keep body editable.
    private func applyListItemEditingTaskStyle( // swiftlint:disable:this function_parameter_count
        to storage: NSMutableAttributedString,
        itemRange: NSRange,
        markerAbsLocation: Int,
        markerLength: Int,
        isChecked: Bool,
        contentStart: Int,
        ordered: Bool,
        nestingLevel: Int,
        ownContentEnd: Int,
        cursorLocation: Int,
        in text: String
    ) {
        let leadingWSLength = markerAbsLocation - itemRange.location

        // Hide leading whitespace for nested items
        if leadingWSLength > 0 {
            let wsRange = NSRange(location: itemRange.location, length: leadingWSLength)
            storage.addAttributes(Self.hiddenAttributes, range: wsRange)
        }

        // Apply paragraph style for indent
        applyListParagraphStyle(to: storage, itemRange: itemRange, ordered: ordered, nestingLevel: nestingLevel, isTask: true, in: text)

        // Render the prefix (marker + checkbox); tasks are always unordered
        applyTaskPrefixRendered(to: storage, itemRange: itemRange, markerAbsLocation: markerAbsLocation, markerLength: markerLength, isChecked: isChecked, nestingLevel: nestingLevel)

        // Body: apply inline styles on own content (exclude nested sublists)
        let ownLength = ownContentEnd - itemRange.location
        if ownLength > contentStart {
            let contentRange = NSRange(location: itemRange.location + contentStart, length: ownLength - contentStart)
            let contentText = (text as NSString).substring(with: contentRange)
            applyBodyContent(to: storage, bodyText: contentText, bodyOffset: contentRange.location,
                             parentNestingLevel: nestingLevel, cursorLocation: cursorLocation, rawMode: true, in: text)
        }
    }

    /// Editing non-task list item with cursor in body zone: render prefix as bullet, keep body editable.
    private func applyListItemEditingBodyStyle( // swiftlint:disable:this function_parameter_count
        to storage: NSMutableAttributedString,
        itemRange: NSRange,
        markerAbsLocation: Int,
        markerLength: Int,
        contentStart: Int,
        ordered: Bool,
        nestingLevel: Int,
        ownContentEnd: Int,
        cursorLocation: Int,
        in text: String
    ) {
        let leadingWSLength = markerAbsLocation - itemRange.location

        // Hide leading whitespace for nested items
        if leadingWSLength > 0 {
            let wsRange = NSRange(location: itemRange.location, length: leadingWSLength)
            storage.addAttributes(Self.hiddenAttributes, range: wsRange)
        }

        // Apply paragraph style for indent
        applyListParagraphStyle(to: storage, itemRange: itemRange, ordered: ordered, nestingLevel: nestingLevel, isTask: false, in: text)

        // Render the marker
        if ordered {
            let markerRange = NSRange(location: markerAbsLocation, length: markerLength)
            storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: markerRange)
        } else {
            // Unordered bullet: hide marker char and tag for BulletLayoutManager to draw
            let charRange = NSRange(location: markerAbsLocation, length: 1)
            storage.addAttributes([
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: 0.001),
                .bulletMarker: true,
                .listNestingLevel: nestingLevel
            ], range: charRange)
            if markerLength > 1 {
                let spaceRange = NSRange(location: markerAbsLocation + 1, length: markerLength - 1)
                storage.addAttributes(Self.hiddenAttributes, range: spaceRange)
            }
        }

        // Body: apply inline styles on own content (exclude nested sublists)
        let ownLength = ownContentEnd - itemRange.location
        if ownLength > contentStart {
            let contentRange = NSRange(location: itemRange.location + contentStart, length: ownLength - contentStart)
            let contentText = (text as NSString).substring(with: contentRange)
            applyBodyContent(to: storage, bodyText: contentText, bodyOffset: contentRange.location,
                             parentNestingLevel: nestingLevel, cursorLocation: cursorLocation, rawMode: true, in: text)
        }
    }

    /// Fully rendered style for non-editing list items.
    private func applyListItemRenderedStyle( // swiftlint:disable:this function_parameter_count
        to storage: NSMutableAttributedString,
        itemRange: NSRange,
        markerAbsLocation: Int,
        markerLength: Int,
        isChecked: Bool?,
        contentStart: Int,
        ordered: Bool,
        nestingLevel: Int,
        ownContentEnd: Int,
        in text: String
    ) {
        let leadingWSLength = markerAbsLocation - itemRange.location

        // Hide leading whitespace for nested items
        if leadingWSLength > 0 {
            let wsRange = NSRange(location: itemRange.location, length: leadingWSLength)
            storage.addAttributes(Self.hiddenAttributes, range: wsRange)
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
                storage.addAttributes(Self.hiddenAttributes, range: spaceRange)
            }
        }

        // Task checkbox content styling (strikethrough for checked)
        // Use ownContentEnd to exclude nested sublists from the strikethrough range.
        if let checked = isChecked, checked {
            let strikethroughEnd = ownContentEnd - itemRange.location
            let strikethroughLength = max(0, strikethroughEnd - contentStart)
            if strikethroughLength > 0 {
                let contentRange = NSRange(location: itemRange.location + contentStart, length: strikethroughLength)
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.tertiaryLabelColor
                ], range: contentRange)
            }
        }

        // Paragraph style
        applyListParagraphStyle(to: storage, itemRange: itemRange, ordered: ordered, nestingLevel: nestingLevel, isTask: isChecked != nil, in: text)

        // Inline styles on own content (exclude nested sublists)
        let ownLength = ownContentEnd - itemRange.location
        if ownLength > contentStart {
            let contentRange = NSRange(location: itemRange.location + contentStart, length: ownLength - contentStart)
            let contentText = (text as NSString).substring(with: contentRange)
            applyBodyContent(to: storage, bodyText: contentText, bodyOffset: contentRange.location,
                             parentNestingLevel: nestingLevel, cursorLocation: nil, rawMode: false, in: text)
        }
    }

    // MARK: - Body content processing

    /// Processes body content line by line.
    /// Lines that look like orphaned empty nested list markers (e.g. "\t- " that swift-markdown
    /// parsed as a setext heading underline instead of a nested list item) are rendered as bullets.
    /// All other lines receive normal inline pattern styling.
    private func applyBodyContent(
        to storage: NSMutableAttributedString,
        bodyText: String,
        bodyOffset: Int,
        parentNestingLevel: Int,
        cursorLocation: Int?,
        rawMode: Bool,
        in fullText: String
    ) {
        var offset = bodyOffset
        let lines = bodyText.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let lineNSLen = (line as NSString).length
            defer { offset += lineNSLen + (i < lines.count - 1 ? 1 : 0) }
            guard lineNSLen > 0 else { continue }

            // Check whether this line is an orphaned empty nested list marker.
            // Pattern: one or more leading tabs/spaces, followed by "- " or "* " (and nothing else).
            let leadingWS = String(line.prefix(while: { $0 == "\t" || $0 == " " }))
            let stripped = String(line.dropFirst(leadingWS.count))
            let leadingWSLen = (leadingWS as NSString).length
            let isOrphanedMarker = leadingWSLen > 0
                && (stripped == "- " || stripped == "* " || stripped == "-" || stripped == "*")

            guard isOrphanedMarker else {
                if rawMode {
                    applyRawInlinePatterns(to: storage, in: line, offset: offset, cursorLocation: cursorLocation ?? -1)
                } else {
                    applyInlinePatterns(to: storage, in: line, offset: offset)
                }
                continue
            }

            // Render the orphaned empty marker as a nested unordered bullet.
            let nestingLevel = parentNestingLevel + 1
            let lineRange = NSRange(location: offset, length: lineNSLen)
            let markerLen = (stripped == "- " || stripped == "* ") ? 2 : 1

            // Hide leading whitespace.
            storage.addAttributes(Self.hiddenAttributes, range: NSRange(location: offset, length: leadingWSLen))
            // Apply paragraph style for the nested level (overrides parent's style for this line).
            applyListParagraphStyle(to: storage, itemRange: lineRange, ordered: false,
                                    nestingLevel: nestingLevel, isTask: false, in: fullText)
            // Hide marker char and tag for BulletLayoutManager.
            let markerAbsLoc = offset + leadingWSLen
            storage.addAttributes([
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: 0.001),
                .bulletMarker: true,
                .listNestingLevel: nestingLevel
            ], range: NSRange(location: markerAbsLoc, length: 1))
            if markerLen > 1 {
                storage.addAttributes(Self.hiddenAttributes,
                                      range: NSRange(location: markerAbsLoc + 1, length: markerLen - 1))
            }
        }
    }

    // MARK: - Task prefix rendering

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
            storage.addAttributes(Self.hiddenAttributes, range: spaceRange)
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
        storage.addAttributes(Self.hiddenAttributes, range: spaceAfterCheckbox)
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

        let font = bodyFont(size: baseFontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = 0.001
        paragraphStyle.paragraphSpacing = 0
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
}
