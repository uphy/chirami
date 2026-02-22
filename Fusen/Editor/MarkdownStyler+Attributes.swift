import AppKit

// MARK: - Custom NSAttributedString keys used by MarkdownStyler and BulletLayoutManager

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

extension NSRange {
    func contains(_ location: Int) -> Bool {
        location >= self.location && location < self.location + self.length
    }
}
