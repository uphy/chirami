import AppKit
import Markdown

// MARK: - Table styling (GFM tables)

extension MarkdownStyler {

    // MARK: - Rendered mode

    func applyTableStyle(to storage: NSMutableAttributedString, table: Table, range: NSRange, in text: String) {
        storage.addAttributes(
            [.foregroundColor: NSColor.clear, .font: bodyFont(size: baseFontSize)],
            range: range
        )

        // Mark separator rows for layout-level collapse by BulletLayoutManager delegate.
        enumerateLines(in: text, range: range) { line, lineStart, _, isLast in
            guard isSeparatorLine(line) else { return }
            let lineLen = (line as NSString).length
            guard lineLen > 0 else { return }
            let length = isLast ? lineLen : lineLen + 1
            storage.addAttribute(.tableSeparatorRow, value: true,
                                 range: NSRange(location: lineStart, length: length))
        }

        // Compute per-row character ranges from the AST so TableOverlayManager can
        // build one combined rect per row even when rows wrap across multiple line fragments.
        // Stored as offsets relative to range.location so they remain valid when text is
        // inserted before the table (NSTextStorage shifts the attribute range but not the
        // values stored inside TableOverlayData).
        var rowCharRanges: [NSRange] = []
        if let headerRange = nsRange(for: table.head, in: text) {
            rowCharRanges.append(NSRange(location: headerRange.location - range.location,
                                         length: headerRange.length))
        }
        for row in table.body.rows {
            if let rowRange = nsRange(for: row, in: text) {
                rowCharRanges.append(NSRange(location: rowRange.location - range.location,
                                              length: rowRange.length))
            }
        }

        let overlayData = TableOverlayData.from(table: table, baseFontSize: baseFontSize, colorScheme: colorScheme,
                                                fontName: fontName, rowCharRanges: rowCharRanges)
        storage.addAttribute(.tableOverlay, value: overlayData, range: range)
    }

    // MARK: - Raw (editing) mode

    func applyTableRawStyle(to storage: NSMutableAttributedString, range: NSRange, in text: String) {
        enumerateLines(in: text, range: range) { line, lineStart, isFirst, _ in
            let lineLen = (line as NSString).length
            guard lineLen > 0 else { return }

            let lineRange = NSRange(location: lineStart, length: lineLen)

            if isSeparatorLine(line) {
                // Dim entire separator row
                storage.addAttributes(
                    [.foregroundColor: NSColor.secondaryLabelColor],
                    range: lineRange
                )
                return
            }

            // Bold monospace for header row, regular for body rows
            let weight: NSFont.Weight = isFirst ? .bold : .regular
            storage.addAttributes(
                [.font: monoFont(size: baseFontSize, weight: weight)],
                range: lineRange
            )

            // Dim pipe characters
            dimTablePipes(in: line, lineStart: lineStart, storage: storage)
        }
    }

    // MARK: - Helpers

    /// Returns true if `line` is a GFM table separator row (e.g. `|---|---|`, `| :--- | ---: |`).
    func isSeparatorLine(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty, stripped.contains("-") else { return false }
        return stripped.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " || $0 == "\t" }
    }

    private func dimTablePipes(in line: String, lineStart: Int, storage: NSMutableAttributedString) {
        let nsLine = line as NSString
        let pipeChar = ("|" as NSString).character(at: 0)
        for i in 0..<nsLine.length where nsLine.character(at: i) == pipeChar {
            storage.addAttributes(
                [.foregroundColor: NSColor.secondaryLabelColor],
                range: NSRange(location: lineStart + i, length: 1)
            )
        }
    }
}
