import AppKit

extension MarkdownStyler {

    func applyThematicBreakStyle(to storage: NSMutableAttributedString, range: NSRange) {
        // Hide the raw syntax (---, ***, ___) and mark the range for custom drawing
        storage.addAttributes(Self.hiddenAttributes, range: range)
        storage.addAttribute(.thematicBreak, value: true, range: range)

        // Set minimum line height so BulletLayoutManager has room to draw the line
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = baseFontSize * 2
        paragraphStyle.maximumLineHeight = baseFontSize * 2
        storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
    }

    func applyRawThematicBreakStyle(to storage: NSMutableAttributedString, range: NSRange) {
        storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: range)
    }
}
