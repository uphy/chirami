import AppKit
import Markdown

// MARK: - TableOverlayData

/// Parsed table data stored as an NSAttributedString attribute value.
/// NSObject subclass so it can be used as an attribute value.
class TableOverlayData: NSObject {
    struct CellData {
        let text: String
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

    static func from(table: Table) -> TableOverlayData {
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

        var headerCells: [CellData] = []
        for (i, cell) in table.head.cells.enumerated() {
            let text = plainText(of: cell)
            headerCells.append(CellData(text: text, alignment: cellAlignment(at: i)))
        }

        var bodyRows: [[CellData]] = []
        for row in table.body.rows {
            var rowCells: [CellData] = []
            for (i, cell) in row.cells.enumerated() {
                let text = plainText(of: cell)
                rowCells.append(CellData(text: text, alignment: cellAlignment(at: i)))
            }
            bodyRows.append(rowCells)
        }

        let columnCount = max(headerCells.count, bodyRows.map { $0.count }.max() ?? 0)
        return TableOverlayData(headerCells: headerCells, bodyRows: bodyRows, columnCount: columnCount)
    }

    private static func plainText(of node: any Markup) -> String {
        if let text = node as? Text { return text.string }
        if node is SoftBreak { return " " }
        if let code = node as? InlineCode { return code.code }
        return node.children.map { plainText(of: $0) }.joined()
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.height > 0, bounds.width > 0, !rowRects.isEmpty else { return }

        let colCount = max(data.columnCount, 1)

        // Measure column widths based on content
        let headerFont = NSFont.systemFont(ofSize: baseFontSize, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: baseFontSize)

        var colWidths: [CGFloat] = Array(repeating: 0, count: colCount)
        for (i, cell) in data.headerCells.enumerated() where i < colCount {
            let w = (cell.text as NSString).size(withAttributes: [.font: headerFont]).width + 16
            colWidths[i] = max(colWidths[i], w)
        }
        for row in data.bodyRows {
            for (i, cell) in row.enumerated() where i < colCount {
                let w = (cell.text as NSString).size(withAttributes: [.font: bodyFont]).width + 16
                colWidths[i] = max(colWidths[i], w)
            }
        }

        // Scale column widths to fill the view
        let totalContentWidth = colWidths.reduce(0, +)
        let scale = totalContentWidth > 0 ? bounds.width / totalContentWidth : 1.0
        let scaledWidths = colWidths.map { $0 * scale }

        // --- Background ---
        // Header row background (rowRects[0] is the header)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        rowRects[0].fill()

        // --- Cell text ---
        func drawCell(text: String, font: NSFont, alignment: NSTextAlignment, colIndex: Int, rowIndex: Int) {
            guard rowIndex < rowRects.count else { return }
            let rowRect = rowRects[rowIndex]
            let x = scaledWidths.prefix(colIndex).reduce(0, +)
            let w = colIndex < scaledWidths.count ? scaledWidths[colIndex] : 0
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.alignment = alignment
            paraStyle.lineBreakMode = .byTruncatingTail

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: noteColor.textColor,
                .paragraphStyle: paraStyle,
            ]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let textY = rowRect.minY + (rowRect.height - textSize.height) / 2
            let drawRect = NSRect(x: x + 8, y: textY, width: w - 16, height: textSize.height)
            (text as NSString).draw(in: drawRect, withAttributes: attrs)
        }

        // Header row
        for (i, cell) in data.headerCells.enumerated() where i < colCount {
            drawCell(text: cell.text, font: headerFont, alignment: cell.alignment, colIndex: i, rowIndex: 0)
        }

        // Body rows
        for (rowIdx, row) in data.bodyRows.enumerated() {
            for (colIdx, cell) in row.enumerated() where colIdx < colCount {
                drawCell(text: cell.text, font: bodyFont, alignment: cell.alignment, colIndex: colIdx, rowIndex: rowIdx + 1)
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
            xPos += scaledWidths[i]
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
