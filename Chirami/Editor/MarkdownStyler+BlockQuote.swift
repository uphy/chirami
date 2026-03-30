import AppKit

// MARK: - Block quote styling

extension MarkdownStyler {

    static let blockQuoteLeftPadding: CGFloat = 16

    func applyBlockQuoteStyle(to storage: NSMutableAttributedString, range: NSRange, in text: String) {
        let nsText = text as NSString
        let indent = Self.blockQuoteLeftPadding

        // Mark entire range for left border drawing by BulletLayoutManager
        storage.addAttributes([
            .blockQuoteBorder: colorScheme.textColor.withAlphaComponent(0.25),
            .foregroundColor: NSColor.secondaryLabelColor
        ], range: range)

        enumerateLines(in: text, range: range) { line, offset, _, isLast in
            let lineLen = (line as NSString).length
            let fullLineLen = isLast ? lineLen : lineLen + 1

            // Paragraph style with indent
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.headIndent = indent
            paraStyle.firstLineHeadIndent = indent
            paraStyle.lineSpacing = 6
            if fullLineLen > 0 {
                let lineRange = NSRange(location: offset, length: fullLineLen)
                storage.addAttributes([.paragraphStyle: paraStyle], range: lineRange)
            }

            // Hide "> " or ">" prefix
            if lineLen > 0, line.hasPrefix(">") {
                let markerLen = line.hasPrefix("> ") ? 2 : 1
                let markerRange = NSRange(location: offset, length: markerLen)
                storage.addAttributes(Self.hiddenAttributes, range: markerRange)

                // Apply inline styles to content after the marker
                let contentStart = markerLen
                if lineLen > contentStart {
                    let contentRange = NSRange(location: offset + contentStart, length: lineLen - contentStart)
                    let contentText = nsText.substring(with: contentRange)
                    applyInlinePatterns(to: storage, in: contentText, offset: contentRange.location)
                }
            }
        }
    }
}
