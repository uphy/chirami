import AppKit

// MARK: - Custom NSAttributedString keys used by MarkdownStyler and BulletLayoutManager

extension NSAttributedString.Key {
    /// Marks a character position as a bullet marker to be drawn by BulletLayoutManager.
    static let bulletMarker = NSAttributedString.Key("chirami.bulletMarker")
    /// Marks a character range as a task checkbox. Value: NSNumber (1=checked, 0=unchecked).
    static let taskCheckbox = NSAttributedString.Key("chirami.taskCheckbox")
    /// Nesting level of a list item (0 = top-level). Value: Int.
    static let listNestingLevel = NSAttributedString.Key("chirami.listNestingLevel")
    /// Marks a range as code block background. Drawn by BulletLayoutManager with padding.
    static let codeBlockBackground = NSAttributedString.Key("chirami.codeBlockBackground")
    /// Marks a range as inline code background. Drawn by BulletLayoutManager with rounded corners.
    static let inlineCodeBackground = NSAttributedString.Key("chirami.inlineCodeBackground")
    /// Marks a range as a block quote. Drawn by BulletLayoutManager with a left border.
    static let blockQuoteBorder = NSAttributedString.Key("chirami.blockQuoteBorder")
    /// Marks a range as a thematic break (---). Drawn by BulletLayoutManager as a horizontal line.
    static let thematicBreak = NSAttributedString.Key("chirami.thematicBreak")
    /// Marks the `!` character of an image. Value: URL string (NSString).
    /// BulletLayoutManager looks up the image from ImageCache and draws it inline.
    static let imageIcon = NSAttributedString.Key("chirami.imageIcon")
    /// Marks a range as a rendered table overlay. Value: TableOverlayData.
    static let tableOverlay = NSAttributedString.Key("chirami.tableOverlay")
    /// Marks a separator row (|---|---|) for layout-level height collapse by BulletLayoutManager.
    static let tableSeparatorRow = NSAttributedString.Key("chirami.tableSeparatorRow")
}

extension NSRange {
    func contains(_ location: Int) -> Bool {
        location >= self.location && location < self.location + self.length
    }
}
