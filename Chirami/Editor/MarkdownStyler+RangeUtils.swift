import AppKit
import Markdown

// MARK: - Source range conversion and utility helpers

extension MarkdownStyler {

    /// Converts a swift-markdown source location to NSRange (UTF-16 units).
    /// swift-markdown columns are 1-based UTF-8 byte offsets; NSRange uses UTF-16.
    func nsRange(for node: any Markup, in text: String) -> NSRange? {
        guard let sourceRange = node.range else { return nil }
        guard let startIdx = stringIndex(line: sourceRange.lowerBound.line,
                                         utf8Column: sourceRange.lowerBound.column,
                                         in: text) else { return nil }

        // cmark-gfm sometimes reports an out-of-bounds end_column for GFM table nodes.
        // Fall back to end-of-line when the normal index calculation fails.
        let endIdx = stringIndex(line: sourceRange.upperBound.line,
                                 utf8Column: sourceRange.upperBound.column,
                                 in: text)
                   ?? endOfLine(line: sourceRange.upperBound.line, in: text)

        guard let endIdx, startIdx <= endIdx else { return nil }
        return NSRange(startIdx..<endIdx, in: text)
    }

    /// Builds an array of line-start indices for `text` (one entry per line, 0-indexed).
    /// Entry 0 = start of line 1, entry 1 = start of line 2, etc.
    func buildLineStarts(in text: String) -> [String.Index] {
        var starts: [String.Index] = [text.startIndex]
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\n" {
                starts.append(text.index(after: i))
            }
            i = text.index(after: i)
        }
        return starts
    }

    /// Returns the exclusive end `String.Index` of the given 1-based line
    /// (points at the `\n` separator, or `endIndex` for the last line).
    private func endOfLine(line: Int, in text: String) -> String.Index? {
        let lineStart: String.Index
        if line >= 1 && line <= lineStartCache.count {
            lineStart = lineStartCache[line - 1]
        } else {
            var current = text.startIndex
            for _ in 1..<line {
                guard let nl = text[current...].firstIndex(of: "\n") else { return nil }
                current = text.index(after: nl)
            }
            lineStart = current
        }
        return text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
    }

    /// Returns the `String.Index` for a given 1-based line and 1-based UTF-8 byte column.
    func stringIndex(line: Int, utf8Column: Int, in text: String) -> String.Index? {
        let lineStart: String.Index
        if line >= 1 && line <= lineStartCache.count {
            lineStart = lineStartCache[line - 1]
        } else {
            var current = text.startIndex
            for _ in 1..<line {
                guard let nl = text[current...].firstIndex(of: "\n") else { return nil }
                current = text.index(after: nl)
            }
            lineStart = current
        }
        let byteOffset = utf8Column - 1
        return text.utf8.index(lineStart, offsetBy: byteOffset, limitedBy: text.utf8.endIndex)
    }

    /// Iterates over lines in `range` of `text`, tracking the absolute offset of each line start.
    func enumerateLines(
        in text: String,
        range: NSRange,
        body: (_ line: String, _ lineStart: Int, _ isFirst: Bool, _ isLast: Bool) -> Void
    ) {
        let lines = (text as NSString).substring(with: range).components(separatedBy: "\n")
        var offset = range.location
        for (i, line) in lines.enumerated() {
            let isFirst = i == 0
            let isLast = i == lines.count - 1
            body(line, offset, isFirst, isLast)
            offset += (line as NSString).length + (isLast ? 0 : 1)
        }
    }

    func overlaps(_ a: NSRange, _ b: NSRange) -> Bool {
        NSIntersectionRange(a, b).length > 0 || a.contains(b.location)
    }

    func isList(_ block: any Markup) -> Bool {
        block is UnorderedList || block is OrderedList
    }
}
