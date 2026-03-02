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

    static func from(table: Table, baseFontSize: CGFloat, noteColor: NoteColor, fontName: String? = nil) -> TableOverlayData {
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

        let headerFont: NSFont
        let bodyFont: NSFont
        if let fontName, let customFont = NSFont(name: fontName, size: baseFontSize) {
            bodyFont = customFont
            headerFont = NSFontManager.shared.convert(customFont, toHaveTrait: .boldFontMask)
        } else {
            headerFont = NSFont.systemFont(ofSize: baseFontSize, weight: .semibold)
            bodyFont = NSFont.systemFont(ofSize: baseFontSize)
        }

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

    private static func attributedText(of cell: Table.Cell, font: NSFont, noteColor: NoteColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in cell.children {
            result.append(InlineMarkupRenderer.attributedText(of: child, font: font, noteColor: noteColor))
        }
        return result
    }
}

// MARK: - TableOverlayManager

/// Manages creation, update, and removal of TableOverlayView instances over a text view.
class TableOverlayManager {
    private var overlays: [Int: TableOverlayView] = [:]

    func removeAll() {
        for overlay in overlays.values {
            overlay.removeFromSuperview()
        }
        overlays.removeAll()
    }

    func update(textView: NSTextView, noteColor: NoteColor, fontSize: CGFloat) {
        guard let storage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)

        let storageRange = NSRange(location: 0, length: storage.length)

        // Collect tableOverlay attributes using longestEffectiveRange to avoid
        // attribute run fragmentation caused by tableSeparatorRow splitting the range.
        var found: [Int: TableOverlayData] = [:]
        storage.enumerateAttribute(.tableOverlay, in: storageRange, options: []) { value, range, _ in
            guard let data = value as? TableOverlayData else { return }
            var fullRange = NSRange()
            storage.attribute(.tableOverlay, at: range.location,
                              longestEffectiveRange: &fullRange,
                              in: storageRange)
            found[fullRange.location] = data
        }

        // Remove overlays no longer present
        let existingKeys = Set(overlays.keys)
        let foundKeys = Set(found.keys)
        for key in existingKeys.subtracting(foundKeys) {
            overlays[key]?.removeFromSuperview()
            overlays.removeValue(forKey: key)
        }

        let containerOrigin = textView.textContainerOrigin
        let containerWidth = textContainer.size.width

        // Create or update overlays
        for (location, data) in found {
            var effectiveRange = NSRange()
            guard storage.attribute(.tableOverlay, at: location,
                                    longestEffectiveRange: &effectiveRange,
                                    in: storageRange) != nil
            else { continue }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: effectiveRange, actualCharacterRange: nil)

            // Collect per-row rects, skipping separator rows
            var rowRects: [NSRect] = []
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, _ in
                let lineCharRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
                if lineCharRange.length > 0,
                   storage.attribute(.tableSeparatorRow, at: lineCharRange.location, effectiveRange: nil) != nil {
                    return  // skip separator
                }
                rowRects.append(lineRect)
            }

            guard let firstRect = rowRects.first, let lastRect = rowRects.last else { continue }
            let minY = firstRect.minY
            let maxY = lastRect.maxY
            guard minY < maxY else { continue }

            let naturalWidths = TableOverlayView.computeColumnWidths(data: data)
            let tableWidth = naturalWidths.reduce(0, +)
            let overlayWidth = tableWidth > 0 ? min(tableWidth, containerWidth) : containerWidth

            let overlayFrame = NSRect(
                x: containerOrigin.x,
                y: containerOrigin.y + minY,
                width: overlayWidth,
                height: maxY - minY
            )

            let localRowRects = rowRects.map { rect in
                NSRect(x: 0, y: rect.minY - minY, width: overlayWidth, height: rect.height)
            }

            if let existing = overlays[location] {
                existing.frame = overlayFrame
                existing.data = data
                existing.noteColor = noteColor
                existing.baseFontSize = fontSize
                existing.rowRects = localRowRects
                existing.needsDisplay = true
            } else {
                let overlay = TableOverlayView(data: data, noteColor: noteColor, baseFontSize: fontSize)
                overlay.frame = overlayFrame
                overlay.rowRects = localRowRects
                textView.addSubview(overlay)
                overlays[location] = overlay
            }
        }
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

        // Header row background (rowRects[0] is the header)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        rowRects[0].fill()

        // Cell text
        for (i, cell) in data.headerCells.enumerated() where i < colCount {
            drawCell(attributedText: cell.attributedText, alignment: cell.alignment,
                     colIndex: i, rowIndex: 0, colWidths: colWidths)
        }
        for (rowIdx, row) in data.bodyRows.enumerated() {
            for (colIdx, cell) in row.enumerated() where colIdx < colCount {
                drawCell(attributedText: cell.attributedText, alignment: cell.alignment,
                         colIndex: colIdx, rowIndex: rowIdx + 1, colWidths: colWidths)
            }
        }

        drawGridLines(colCount: colCount, colWidths: colWidths)
    }

    private func drawCell(
        attributedText: NSAttributedString,
        alignment: NSTextAlignment,
        colIndex: Int,
        rowIndex: Int,
        colWidths: [CGFloat]
    ) {
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

    private func drawGridLines(colCount: Int, colWidths: [CGFloat]) {
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
        if !data.bodyRows.isEmpty, rowRects.count > 1 {
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
