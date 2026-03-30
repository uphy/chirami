import AppKit

// MARK: - Heading styling

extension MarkdownStyler {

    func headingFontSize(for level: Int) -> CGFloat {
        let multiplier: CGFloat
        switch level {
        case 1: multiplier = 1.7
        case 2: multiplier = 1.43
        case 3: multiplier = 1.21
        default: multiplier = 1.07
        }
        return (baseFontSize * multiplier).rounded()
    }

    func applyHeadingStyle(level: Int, to storage: NSMutableAttributedString, range: NSRange) {
        storage.addAttributes([
            .font: boldFont(size: headingFontSize(for: level)),
            .foregroundColor: colorScheme.textColor
        ], range: range)
    }

    func hideMarkdownSyntax(
        in storage: NSMutableAttributedString,
        range: NSRange,
        text: String,
        prefix: String
    ) {
        let prefixLen = prefix.count
        guard range.length > prefixLen else { return }
        let prefixRange = NSRange(location: range.location, length: prefixLen)
        storage.addAttributes(Self.hiddenAttributes, range: prefixRange)
    }
}
