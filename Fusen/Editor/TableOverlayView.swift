import AppKit
import Markdown

// MARK: - TableOverlayData

/// Parsed table data stored as an NSAttributedString attribute value.
/// NSObject subclass so it can be used as an attribute value.
class TableOverlayData: NSObject {
    struct CellData {
        let attributedText: NSAttributedString
        let alignment: NSTextAlignment
    }

    let headerCells: [CellData]
    let bodyRows: [[CellData]]
    let columnCount: Int

    init(headerCells: [CellData], bodyRows: [[CellData]], columnCount: Int) {
        self.headerCells = headerCells
        self.bodyRows = bodyRows
        self.columnCount = columnCount
    }

    static func from(table: Table, baseFontSize: CGFloat, noteColor: NoteColor) -> TableOverlayData {
        let alignments = table.columnAlignments.map { alignment -> NSTextAlignment in
            switch alignment {
            case .left: return .left
            case .right: return .right
            case .center: return .center
            case .none: return .left
            }
        }

        func cellAlignment(at index: Int) -> NSTextAlignment {
            guard index < alignments.count else { return .left }
            return alignments[index]
        }

        let headerFont = NSFont.systemFont(ofSize: baseFontSize, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: baseFontSize)

        var headerCells: [CellData] = []
        for (i, cell) in table.head.cells.enumerated() {
            let attrText = attributedText(of: cell, font: headerFont, noteColor: noteColor)
            headerCells.append(CellData(attributedText: attrText, alignment: cellAlignment(at: i)))
        }

        var bodyRows: [[CellData]] = []
        for row in table.body.rows {
            var rowCells: [CellData] = []
            for (i, cell) in row.cells.enumerated() {
                let attrText = attributedText(of: cell, font: bodyFont, noteColor: noteColor)
                rowCells.append(CellData(attributedText: attrText, alignment: cellAlignment(at: i)))
            }
            bodyRows.append(rowCells)
        }

        let columnCount = max(headerCells.count, bodyRows.map { $0.count }.max() ?? 0)
        return TableOverlayData(headerCells: headerCells, bodyRows: bodyRows, columnCount: columnCount)
    }

    // MARK: - AST -> NSAttributedString

    /// Recursively builds an NSAttributedString from an inline AST node.
    private static func attributedText(of node: any Markup, font: NSFont, noteColor: NoteColor) -> NSAttributedString {
        if let textNode = node as? Text {
            return NSAttributedString(string: textNode.string, attributes: [
                .font: font,
                .foregroundColor: noteColor.textColor,
            ])
        }

        if node is SoftBreak || node is LineBreak {
            return NSAttributedString(string: " ", attributes: [
                .font: font,
                .foregroundColor: noteColor.textColor,
            ])
        }

        if node is Strong {
            let boldFont = NSFont.systemFont(ofSize: font.pointSize, weight: .bold)
            let result = NSMutableAttributedString()
            for child in node.children {
                result.append(attributedText(of: child, font: boldFont, noteColor: noteColor))
            }
            return result
        }

        if node is Emphasis {
            let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            let result = NSMutableAttributedString()
            for child in node.children {
                result.append(attributedText(of: child, font: italicFont, noteColor: noteColor))
            }
            return result
        }

        if let code = node as? InlineCode {
            let codeFont = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            return NSAttributedString(string: code.code, attributes: [
                .font: codeFont,
                .foregroundColor: NSColor.systemOrange,
                .inlineCodeBackground: NSColor.labelColor.withAlphaComponent(0.08),
            ])
        }

        if let link = node as? Link {
            let result = NSMutableAttributedString()
            for child in link.children {
                result.append(attributedText(of: child, font: font, noteColor: noteColor))
            }
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: noteColor.linkColor]
            if let dest = link.destination, let url = URL(string: dest) {
                attrs[.link] = url
            }
            result.addAttributes(attrs, range: NSRange(location: 0, length: result.length))
            return result
        }

        if node is Strikethrough {
            let result = NSMutableAttributedString()
            for child in node.children {
                result.append(attributedText(of: child, font: font, noteColor: noteColor))
            }
            result.addAttribute(
                .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                range: NSRange(location: 0, length: result.length))
            return result
        }

        // Default: recurse over children (handles Table.Cell and unknown containers)
        let result = NSMutableAttributedString()
        for child in node.children {
            result.append(attributedText(of: child, font: font, noteColor: noteColor))
        }
        return result
    }

    /// Entry point for a Table.Cell node.
    private static func attributedText(of cell: Table.Cell, font: NSFont, noteColor: NoteColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in cell.children {
            result.append(attributedText(of: child, font: font, noteColor: noteColor))
        }
        return result
    }
}

// MARK: - TableOverlayView

/// NSView that draws a grid table over invisible table text.
/// Clicks pass through to the underlying NSTextView so the cursor enters raw mode.
class TableOverlayView: NSView {
    var data: TableOverlayData
    var noteColor: NoteColor
    var baseFontSize: CGFloat
    /// Per-row rects in local coordinates (y=0 at top), separator rows excluded.
    var rowRects: [NSRect] = []

    init(data: TableOverlayData, noteColor: NoteColor, baseFontSize: CGFloat) {
        self.data = data
        self.noteColor = noteColor
        self.baseFontSize = baseFontSize
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // Match the text view's coordinate system (y increases downward).
    override var isFlipped: Bool { true }

    // Pass all clicks through to the NSTextView below.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Returns natural column widths based on attributed cell content.
    static func computeColumnWidths(data: TableOverlayData) -> [CGFloat] {
        let colCount = max(data.columnCount, 1)
        var colWidths: [CGFloat] = Array(repeating: 0, count: colCount)
        for (i, cell) in data.headerCells.enumerated() where i < colCount {
            let w = cell.attributedText.size().width + 16
            colWidths[i] = max(colWidths[i], w)
        }
        for row in data.bodyRows {
            for (i, cell) in row.enumerated() where i < colCount {
                let w = cell.attributedText.size().width + 16
                colWidths[i] = max(colWidths[i], w)
            }
        }
        return colWidths
    }

    func computeColumnWidths() -> [CGFloat] {
        Self.computeColumnWidths(data: data)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.height > 0, bounds.width > 0, !rowRects.isEmpty else { return }

        let colCount = max(data.columnCount, 1)
        let colWidths = computeColumnWidths()

        // --- Background ---
        // Header row background (rowRects[0] is the header)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        rowRects[0].fill()

        // --- Cell text ---
        func drawCell(attributedText: NSAttributedString, alignment: NSTextAlignment, colIndex: Int, rowIndex: Int) {
            guard rowIndex < rowRects.count else { return }
            let rowRect = rowRects[rowIndex]
            let x = colWidths.prefix(colIndex).reduce(0, +)
            let w = colIndex < colWidths.count ? colWidths[colIndex] : 0

            let mutable = NSMutableAttributedString(attributedString: attributedText)
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.alignment = alignment
            paraStyle.lineBreakMode = .byTruncatingTail
            let fullRange = NSRange(location: 0, length: mutable.length)
            mutable.addAttribute(.paragraphStyle, value: paraStyle, range: fullRange)

            let textSize = mutable.size()
            let textY = rowRect.minY + (rowRect.height - textSize.height) / 2
            let drawRect = NSRect(x: x + 8, y: textY, width: w - 16, height: textSize.height)

            // Draw inline code backgrounds using a temporary layout stack
            var hasCodeBackground = false
            mutable.enumerateAttribute(.inlineCodeBackground, in: fullRange, options: []) { value, _, _ in
                if value != nil { hasCodeBackground = true }
            }
            if hasCodeBackground {
                let textStorage = NSTextStorage(attributedString: mutable)
                let layoutManager = NSLayoutManager()
                let textContainer = NSTextContainer(
                    size: CGSize(width: drawRect.width, height: CGFloat.greatestFiniteMagnitude))
                textContainer.lineFragmentPadding = 0
                layoutManager.addTextContainer(textContainer)
                textStorage.addLayoutManager(layoutManager)

                mutable.enumerateAttribute(.inlineCodeBackground, in: fullRange, options: []) { value, range, _ in
                    guard let color = value as? NSColor else { return }
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    let bgRect = rect.offsetBy(dx: drawRect.minX, dy: drawRect.minY).insetBy(dx: -2, dy: -1)
                    color.setFill()
                    NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()
                }
            }

            mutable.draw(in: drawRect)
        }

        // Header row
        for (i, cell) in data.headerCells.enumerated() where i < colCount {
            drawCell(attributedText: cell.attributedText, alignment: cell.alignment, colIndex: i, rowIndex: 0)
        }

        // Body rows
        for (rowIdx, row) in data.bodyRows.enumerated() {
            for (colIdx, cell) in row.enumerated() where colIdx < colCount {
                drawCell(
                    attributedText: cell.attributedText, alignment: cell.alignment,
                    colIndex: colIdx, rowIndex: rowIdx + 1)
            }
        }

        // --- Grid lines ---
        NSColor.separatorColor.setStroke()
        let gridPath = NSBezierPath()
        gridPath.lineWidth = 0.5

        // Outer border
        gridPath.appendRect(bounds)

        // Horizontal lines between body rows (r=1 is the thick divider, skip it here)
        for r in 2..<rowRects.count {
            let y = rowRects[r].minY
            gridPath.move(to: NSPoint(x: 0, y: y))
            gridPath.line(to: NSPoint(x: bounds.width, y: y))
        }

        // Vertical lines between columns
        var xPos: CGFloat = 0
        for i in 0..<colCount - 1 {
            xPos += colWidths[i]
            gridPath.move(to: NSPoint(x: xPos, y: 0))
            gridPath.line(to: NSPoint(x: xPos, y: bounds.height))
        }
        gridPath.stroke()

        // Thicker header/body divider
        if data.bodyRows.count > 0, rowRects.count > 1 {
            let separatorY = rowRects[1].minY
            let thickPath = NSBezierPath()
            thickPath.lineWidth = 1.5
            NSColor.separatorColor.setStroke()
            thickPath.move(to: NSPoint(x: 0, y: separatorY))
            thickPath.line(to: NSPoint(x: bounds.width, y: separatorY))
            thickPath.stroke()
        }
    }
}
