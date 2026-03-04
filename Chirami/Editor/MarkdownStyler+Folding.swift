import AppKit
import Markdown

// MARK: - Foldable block model

/// Represents a block that can be folded (heading section or list item with children).
struct FoldableBlock {
    /// 1-based source line number of the block's first line (as reported by swift-markdown).
    let startLine: Int
    let kind: Kind

    enum Kind {
        case heading(level: Int)
        /// A list item that has at least one nested sub-list.
        case listItem
    }
}

// MARK: - Folding support in MarkdownStyler

extension MarkdownStyler {

    // MARK: - Enumerate foldable blocks

    /// Returns all foldable blocks in the document (parses text into a Document).
    func enumerateFoldableBlocks(in text: String) -> [FoldableBlock] {
        guard !text.isEmpty else { return [] }
        return enumerateFoldableBlocks(from: Document(parsing: text))
    }

    /// Returns all foldable blocks from a pre-parsed Document.
    func enumerateFoldableBlocks(from doc: Document) -> [FoldableBlock] {
        var blocks: [FoldableBlock] = []
        for block in doc.children {
            guard let sourceRange = block.range else { continue }
            let line = sourceRange.lowerBound.line  // 1-based
            if let heading = block as? Heading {
                blocks.append(FoldableBlock(startLine: line, kind: .heading(level: heading.level)))
            } else if isList(block) {
                collectFoldableListItems(from: block, into: &blocks)
            }
        }
        return blocks
    }

    /// Recursively collects list items that have at least one nested sub-list.
    private func collectFoldableListItems(from list: any Markup, into blocks: inout [FoldableBlock]) {
        for child in list.children {
            guard let item = child as? ListItem,
                  let sourceRange = item.range else { continue }
            let hasNestedList = item.children.contains(where: { isList($0) })
            if hasNestedList {
                blocks.append(FoldableBlock(startLine: sourceRange.lowerBound.line, kind: .listItem))
            }
            // Recurse regardless so deeply-nested foldable items are found
            for subChild in item.children where isList(subChild) {
                collectFoldableListItems(from: subChild, into: &blocks)
            }
        }
    }

    // MARK: - Apply fold state

    /// Overlays fold state onto an already-styled attributed string.
    /// Called at the end of style(_:cursorLocation:foldedLines:) when foldedLines is non-empty.
    /// lineStartCache must be populated when this is called.
    func applyFoldState(
        to storage: NSMutableAttributedString,
        doc: Document,
        text: String,
        foldedLines: Set<Int>
    ) {
        let nsText = text as NSString
        let topLevelBlocks = Array(doc.children)

        for (i, block) in topLevelBlocks.enumerated() {
            guard let sourceRange = block.range else { continue }
            let startLine = sourceRange.lowerBound.line

            if block is Heading && foldedLines.contains(startLine) {
                guard let blockRange = nsRange(for: block, in: text) else { continue }
                let headingLineRange = nsText.lineRange(
                    for: NSRange(location: blockRange.location, length: 0))
                let hiddenStart = headingLineRange.location + headingLineRange.length
                let sectionEnd = headingSectionEnd(index: i, allBlocks: topLevelBlocks, in: text)

                if hiddenStart < sectionEnd {
                    applyFoldedAttributes(to: storage,
                                          range: NSRange(location: hiddenStart, length: sectionEnd - hiddenStart))
                    applyFoldEllipsis(to: storage, lineRange: headingLineRange, line: startLine)
                }

            } else if isList(block) {
                applyListItemFoldState(to: storage, list: block, text: text, nsText: nsText,
                                       foldedLines: foldedLines)
            }
        }
    }

    /// Recursively hides the nested content of folded list items.
    private func applyListItemFoldState(
        to storage: NSMutableAttributedString,
        list: any Markup,
        text: String,
        nsText: NSString,
        foldedLines: Set<Int>
    ) {
        for child in list.children {
            guard let item = child as? ListItem,
                  let sourceRange = item.range else { continue }
            let startLine = sourceRange.lowerBound.line

            if foldedLines.contains(startLine) {
                guard let itemRange = nsRange(for: item, in: text) else { continue }
                // Hide everything after the item's first line (i.e., all nested content)
                let firstLineRange = nsText.lineRange(
                    for: NSRange(location: itemRange.location, length: 0))
                let hiddenStart = firstLineRange.location + firstLineRange.length
                let hiddenEnd = itemRange.location + itemRange.length

                if hiddenStart < hiddenEnd {
                    applyFoldedAttributes(to: storage,
                                          range: NSRange(location: hiddenStart, length: hiddenEnd - hiddenStart))
                    applyFoldEllipsis(to: storage, lineRange: firstLineRange, line: startLine)
                }
                // Skip recursion — nested content is already hidden
                continue
            }

            // Not folded: recurse into nested lists
            for subChild in item.children where isList(subChild) {
                applyListItemFoldState(to: storage, list: subChild, text: text, nsText: nsText,
                                       foldedLines: foldedLines)
            }
        }
    }

    // MARK: - Helpers

    /// Marks the newline at the end of a visible fold line with the `.foldEllipsis` attribute.
    /// Value is the 1-based line number, used for hit-testing to determine which fold to toggle.
    private func applyFoldEllipsis(to storage: NSMutableAttributedString, lineRange: NSRange, line: Int) {
        let ellipsisPos = lineRange.location + lineRange.length - 1
        guard ellipsisPos >= lineRange.location, ellipsisPos < storage.length else { return }
        storage.addAttribute(.foldEllipsis, value: line, range: NSRange(location: ellipsisPos, length: 1))
    }

    private func applyFoldedAttributes(to storage: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0, range.location + range.length <= storage.length else { return }
        storage.addAttributes([
            .foregroundColor: NSColor.clear,
            .font: NSFont.systemFont(ofSize: 0.001),
            .foldedContent: true
        ], range: range)
    }

    /// Returns the character index where the section of heading at `index` ends.
    private func headingSectionEnd(index: Int, allBlocks: [any Markup], in text: String) -> Int {
        guard let currentHeading = allBlocks[index] as? Heading else { return text.utf16.count }
        let level = currentHeading.level
        for j in (index + 1)..<allBlocks.count {
            if let nextHeading = allBlocks[j] as? Heading, nextHeading.level <= level {
                if let nextRange = nsRange(for: nextHeading, in: text) {
                    return nextRange.location
                }
            }
        }
        return text.utf16.count
    }
}
