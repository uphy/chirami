import AppKit

extension MarkdownStyler {

    func applyThematicBreakStyle(to storage: NSMutableAttributedString, range: NSRange) {
        // Make text transparent but keep the base font size so NSLayoutManager
        // computes proper line fragment height. Using font size 0.001 (hiddenAttributes)
        // causes the line fragment to collapse, misplacing the drawn horizontal rule.
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
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
