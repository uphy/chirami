import AppKit

/// Custom layout manager that draws bullet points (•) over hidden unordered list markers.
class BulletLayoutManager: NSLayoutManager {

    var baseFontSize: CGFloat = 14
    var fontName: String?

    /// Rects of drawn images keyed by character index (in view coordinates).
    private(set) var drawnImageRects: [Int: NSRect] = [:]

    /// Rects of drawn delete buttons keyed by character index (in view coordinates).
    private(set) var drawnDeleteButtonRects: [Int: NSRect] = [:]

    /// Rects of drawn fold ellipsis badges keyed by character index (in view coordinates).
    private(set) var drawnEllipsisRects: [Int: NSRect] = [:]

    /// Character index of the currently hovered image (set by MarkdownTextView).
    var hoveredImageCharIndex: Int?

    /// Temporary width overrides during drag resize, keyed by character index.
    var dragOverrideWidths: [Int: CGFloat] = [:]

    override init() {
        super.init()
        self.delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.delegate = self
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage,
              let textContainer = textContainers.first else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        drawCodeBlockBackgrounds(in: textStorage, charRange: charRange, origin: origin,
                                 containerWidth: textContainer.size.width)
        drawBlockQuoteBorders(in: textStorage, charRange: charRange, origin: origin)
        drawThematicBreaks(in: textStorage, charRange: charRange, origin: origin,
                           containerWidth: textContainer.size.width)
        drawInlineCodeBackgrounds(in: textStorage, charRange: charRange, origin: origin,
                                  textContainer: textContainer)
    }

    private func drawCodeBlockBackgrounds(
        in textStorage: NSTextStorage, charRange: NSRange, origin: NSPoint, containerWidth: CGFloat
    ) {
        textStorage.enumerateAttribute(.codeBlockBackground, in: charRange, options: []) { value, attrRange, _ in
            guard let color = value as? NSColor else { return }
            let glyphRange = glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)

            var minY: CGFloat = .greatestFiniteMagnitude
            var maxY: CGFloat = 0
            enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                minY = min(minY, lineRect.origin.y)
                maxY = max(maxY, lineRect.origin.y + lineRect.height)
            }
            guard minY < maxY else { return }

            let bgRect = NSRect(x: origin.x, y: origin.y + minY, width: containerWidth, height: maxY - minY)
            color.setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6).fill()
        }
    }

    private func drawBlockQuoteBorders(
        in textStorage: NSTextStorage, charRange: NSRange, origin: NSPoint
    ) {
        textStorage.enumerateAttribute(.blockQuoteBorder, in: charRange, options: []) { value, attrRange, _ in
            guard let color = value as? NSColor else { return }

            // Trim trailing newlines so we don't include an extra empty line fragment
            var trimmedRange = attrRange
            let str = textStorage.string as NSString
            while trimmedRange.length > 0,
                  str.substring(with: NSRange(location: trimmedRange.location + trimmedRange.length - 1, length: 1)) == "\n" {
                trimmedRange.length -= 1
            }
            guard trimmedRange.length > 0 else { return }

            let glyphRange = glyphRange(forCharacterRange: trimmedRange, actualCharacterRange: nil)

            // Use usedRect (not lineRect) to get tight bounds without extra line spacing
            var minY: CGFloat = .greatestFiniteMagnitude
            var maxY: CGFloat = 0
            enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                minY = min(minY, usedRect.origin.y)
                maxY = max(maxY, usedRect.origin.y + usedRect.height)
            }

            // Subtract lineSpacing of the last line to avoid the border extending below the text
            let lastCharIndex = trimmedRange.location + trimmedRange.length - 1
            if let paragraphStyle = textStorage.attribute(.paragraphStyle, at: lastCharIndex, effectiveRange: nil) as? NSParagraphStyle {
                maxY -= paragraphStyle.lineSpacing
            }
            guard minY < maxY else { return }

            let borderWidth: CGFloat = 3
            let borderRect = NSRect(
                x: origin.x + 4, y: origin.y + minY, width: borderWidth, height: maxY - minY)
            color.setFill()
            NSBezierPath(roundedRect: borderRect, xRadius: borderWidth / 2, yRadius: borderWidth / 2).fill()
        }
    }

    private func drawThematicBreaks(
        in textStorage: NSTextStorage, charRange: NSRange, origin: NSPoint, containerWidth: CGFloat
    ) {
        textStorage.enumerateAttribute(.thematicBreak, in: charRange, options: []) { value, attrRange, _ in
            guard value != nil else { return }
            // Use the first glyph's line fragment to determine the Y position.
            // Previously, enumerateLineFragments iterated all fragments and kept the last,
            // which could place the rule at the wrong position when the range includes
            // a trailing newline (swift-markdown ranges end at the next line's start).
            let firstGlyphIndex = glyphIndexForCharacter(at: attrRange.location)
            let lineRect = lineFragmentRect(forGlyphAt: firstGlyphIndex, effectiveRange: nil)
            guard lineRect != .zero else { return }
            let y = (origin.y + lineRect.midY).rounded() - 0.5
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(rect: NSRect(x: origin.x + 8, y: y, width: containerWidth - 16, height: 1)).fill()
        }
    }

    private func drawInlineCodeBackgrounds(
        in textStorage: NSTextStorage, charRange: NSRange, origin: NSPoint, textContainer: NSTextContainer
    ) {
        textStorage.enumerateAttribute(.inlineCodeBackground, in: charRange, options: []) { value, attrRange, _ in
            guard let color = value as? NSColor else { return }
            let glyphRange = glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            let rect = boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let paragraphStyle = textStorage.attribute(.paragraphStyle, at: attrRange.location, effectiveRange: nil) as? NSParagraphStyle
            let lineSpacing = paragraphStyle?.lineSpacing ?? 0
            let tightRect = NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height - lineSpacing)
            let bgRect = tightRect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -2, dy: -1)
            color.setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()
        }
    }

    override func drawUnderline(
        forGlyphRange glyphRange: NSRange,
        underlineType underlineVal: NSUnderlineStyle,
        baselineOffset: CGFloat,
        lineFragmentRect lineRect: NSRect,
        lineFragmentGlyphRange lineGlyphRange: NSRange,
        containerOrigin: NSPoint
    ) {
        // Clip the underline drawing to the bounding rect of the actual glyphs.
        // NSTextView's link underline can extend across adjacent hidden characters
        // (0.001pt font) used for Markdown syntax hiding, causing the underline to
        // stretch from the line start to the link text.
        guard let textContainer = textContainers.first,
              let ctx = NSGraphicsContext.current?.cgContext else {
            super.drawUnderline(forGlyphRange: glyphRange, underlineType: underlineVal, baselineOffset: baselineOffset, lineFragmentRect: lineRect, lineFragmentGlyphRange: lineGlyphRange, containerOrigin: containerOrigin)
            return
        }

        let glyphBounds = boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let clipRect = glyphBounds.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
            .insetBy(dx: 0, dy: -4)

        ctx.saveGState()
        ctx.clip(to: clipRect)
        super.drawUnderline(forGlyphRange: glyphRange, underlineType: underlineVal, baselineOffset: baselineOffset, lineFragmentRect: lineRect, lineFragmentGlyphRange: lineGlyphRange, containerOrigin: containerOrigin)
        ctx.restoreGState()
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        // Draw bullet markers (•)
        textStorage.enumerateAttribute(.bulletMarker, in: charRange, options: []) { value, range, _ in
            guard value != nil else { return }
            guard textStorage.attribute(.foldedContent, at: range.location, effectiveRange: nil) == nil else { return }
            drawSymbol("•", at: range, origin: origin, color: NSColor.secondaryLabelColor, fontSize: baseFontSize)
        }

        // Draw task checkboxes using SF Symbols
        textStorage.enumerateAttribute(.taskCheckbox, in: charRange, options: []) { value, range, _ in
            guard let number = value as? NSNumber else { return }
            guard textStorage.attribute(.foldedContent, at: range.location, effectiveRange: nil) == nil else { return }
            let checked = number.boolValue
            let symbolName = checked ? "checkmark.square.fill" : "square"
            let uncheckedColor = NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                    return NSColor(white: 0.5, alpha: 1.0)
                } else {
                    return NSColor(white: 0.62, alpha: 1.0)
                }
            }
            let color = checked ? NSColor.controlAccentColor : uncheckedColor
            drawSFSymbol(symbolName, at: range, origin: origin, color: color, size: baseFontSize)
        }

        // Clear rects only for the current character range being redrawn
        clearDrawnRects(&drawnImageRects, in: charRange)
        clearDrawnRects(&drawnDeleteButtonRects, in: charRange)

        // Draw fold ellipsis indicators
        clearDrawnRects(&drawnEllipsisRects, in: charRange)
        textStorage.enumerateAttribute(.foldEllipsis, in: charRange, options: []) { value, range, _ in
            guard value is Int else { return }
            self.drawFoldEllipsis(at: range, origin: origin)
        }

        // Draw inline images (or a placeholder icon while loading)
        textStorage.enumerateAttribute(.imageIcon, in: charRange, options: []) { value, range, _ in
            guard let urlString = value as? String else { return }
            guard textStorage.attribute(.foldedContent, at: range.location, effectiveRange: nil) == nil else { return }
            let widthNumber = textStorage.attribute(.imageWidth, at: range.location, effectiveRange: nil) as? NSNumber
            let requestedWidth: CGFloat? = widthNumber.map { CGFloat($0.doubleValue) }
            if let image = ImageCache.shared.image(for: urlString) {
                drawInlineImage(image, at: range, origin: origin, requestedWidth: requestedWidth)
            } else {
                drawSFSymbolAtGlyphPosition("photo", at: range, origin: origin, color: NSColor.secondaryLabelColor, size: baseFontSize)
            }
        }
    }

    /// Computes the baseline Y offset within the line fragment rect using a reference font.
    /// Hidden marker characters use a tiny font (0.001pt), which causes
    /// `self.location(forGlyphAt:)` to return an incorrect baseline for empty list items.
    /// Computed directly from font metrics to avoid the last-line issue where NSLayoutManager
    /// does not include lineSpacing in the last line's fragment rect height.
    private func referenceFont(size: CGFloat) -> NSFont {
        if let fontName, let font = NSFont(name: fontName, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size)
    }

    private func baselineOffset(forGlyphAt glyphIndex: Int, fontSize: CGFloat) -> CGFloat {
        let refFont = referenceFont(size: fontSize)
        // minimumLineHeight matches applyListParagraphStyle: ceil(ascender - descender + leading)
        // baseline = minimumLineHeight + descender
        return ceil(refFont.ascender - refFont.descender + refFont.leading) + refFont.descender
    }

    private func nestingLevel(at charLocation: Int) -> Int {
        guard let textStorage = textStorage else { return 0 }
        return textStorage.attribute(.listNestingLevel, at: charLocation, effectiveRange: nil) as? Int ?? 0
    }

    private struct GlyphPosition {
        let glyphIndex: Int
        let lineRect: NSRect
        let level: Int
        let baselineY: CGFloat
    }

    private func glyphPosition(at range: NSRange, origin: NSPoint, fontSize: CGFloat) -> GlyphPosition? {
        let glyphIndex = glyphIndexForCharacter(at: range.location)
        guard textContainer(forGlyphAt: glyphIndex, effectiveRange: nil) != nil else { return nil }
        let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let level = nestingLevel(at: range.location)
        // Prefer the actual baseline from the first visible content character in the line.
        // Hidden marker characters (0.001pt font) cause location(forGlyphAt:) to return an
        // incorrect baseline; for non-empty items a content character gives the true value.
        let baselineFromTop = contentCharBaselineOffset(near: range.location, lineRect: lineRect)
            ?? baselineOffset(forGlyphAt: glyphIndex, fontSize: fontSize)
        let baselineY = origin.y + lineRect.origin.y + baselineFromTop
        return GlyphPosition(glyphIndex: glyphIndex, lineRect: lineRect, level: level, baselineY: baselineY)
    }

    /// Scans forward from `charLocation` to find the first content character (non-hidden font)
    /// in the same line fragment and returns its glyph location y, which equals the actual
    /// baseline offset from the line fragment's top as used by NSLayoutManager.
    /// Returns nil when no content character exists in the line (e.g., empty list items).
    private func contentCharBaselineOffset(near charLocation: Int, lineRect: NSRect) -> CGFloat? {
        guard let textStorage = textStorage else { return nil }
        let str = textStorage.string as NSString
        let startLoc = charLocation + 1
        let totalLength = str.length
        guard startLoc < totalLength else { return nil }

        // Compute the search range bounded to the current line (excluding trailing newline).
        // This lets enumerateAttribute skip entire hidden-font runs atomically instead of
        // checking each character, avoiding per-character attribute lookups in the hot path.
        let lineRange = str.lineRange(for: NSRange(location: charLocation, length: 0))
        let searchEnd = (lineRange.length > 0 && str.character(at: lineRange.upperBound - 1) == 0x0A)
            ? lineRange.upperBound - 1
            : lineRange.upperBound
        guard startLoc < searchEnd else { return nil }
        let searchRange = NSRange(location: startLoc, length: searchEnd - startLoc)

        var result: CGFloat?
        textStorage.enumerateAttribute(.font, in: searchRange, options: []) { value, runRange, stop in
            guard let font = value as? NSFont, font.pointSize >= 1.0 else { return }
            let contentGlyphIndex = glyphIndexForCharacter(at: runRange.location)
            let contentLineRect = lineFragmentRect(forGlyphAt: contentGlyphIndex, effectiveRange: nil)
            guard abs(contentLineRect.origin.y - lineRect.origin.y) < 1.0 else {
                stop.pointee = true
                return
            }
            result = location(forGlyphAt: contentGlyphIndex).y
            stop.pointee = true
        }
        return result
    }

    private func drawSFSymbol(_ name: String, at range: NSRange, origin: NSPoint, color: NSColor, size: CGFloat) {
        guard let pos = glyphPosition(at: range, origin: origin, fontSize: size) else { return }

        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }

        let tinted = image.tinted(with: color)
        let imageSize = tinted.size
        let x = origin.x + pos.lineRect.origin.x + 2 + CGFloat(pos.level) * 20
        let textFont = referenceFont(size: size)
        let textCenterY = pos.baselineY - textFont.capHeight / 2
        let y = textCenterY - imageSize.height / 2
        tinted.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height))
    }

    /// Draws a loaded image inline at the glyph position of the `!` marker character.
    /// Scales the image to fit the line fragment height while capping at the container width.
    /// When `requestedWidth` is specified, the image is drawn at that width (clamped to available width).
    /// During drag resize, `dragOverrideWidths` takes priority over `requestedWidth`.
    private func drawInlineImage(_ image: NSImage, at range: NSRange, origin: NSPoint, requestedWidth: CGFloat? = nil) {
        let glyphIndex = glyphIndexForCharacter(at: range.location)
        guard textContainer(forGlyphAt: glyphIndex, effectiveRange: nil) != nil else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let glyphLocation = location(forGlyphAt: glyphIndex)
        let availableWidth = (textContainers.first?.size.width ?? 380) - glyphLocation.x - 16

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        // Drag override width takes priority over requestedWidth
        let effectiveWidth: CGFloat? = dragOverrideWidths[range.location] ?? requestedWidth

        let maxWidth: CGFloat
        if let effective = effectiveWidth {
            maxWidth = min(effective, availableWidth)
        } else {
            maxWidth = availableWidth
        }
        let isDragOverride = dragOverrideWidths[range.location] != nil
        let scale: CGFloat
        if effectiveWidth != nil {
            // Explicit width (from alt text or drag): scale to the requested width directly.
            // Line height was reserved based on the same scale, so no additional constraint needed.
            scale = maxWidth / imageSize.width
        } else {
            // No explicit width: fit within the line fragment height to avoid overflow.
            scale = min(maxWidth / imageSize.width, lineRect.height / imageSize.height)
        }
        let drawWidth = (imageSize.width * scale).rounded()
        let drawHeight = (imageSize.height * scale).rounded()

        let x = origin.x + lineRect.origin.x + glyphLocation.x
        let y: CGFloat
        if isDragOverride {
            // Top-align during drag to avoid gap above image
            y = origin.y + lineRect.origin.y
        } else {
            y = origin.y + lineRect.origin.y + ((lineRect.height - drawHeight) / 2).rounded()
        }

        // NSTextView is flipped (y increases downward). CGContext.draw(cgImage:in:) assumes
        // unflipped coordinates (y increases upward). Apply an explicit flip so the image
        // appears right-side up: translate to the image's bottom-left in the flipped view,
        // then negate the y-axis so CGContext's "up" maps to the screen's "up".
        ctx.saveGState()
        ctx.translateBy(x: x, y: y + drawHeight)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: drawWidth, height: drawHeight))
        ctx.restoreGState()

        // Record the drawn rect for hit-testing (view coordinates)
        let imageRect = NSRect(x: x, y: y, width: drawWidth, height: drawHeight)
        drawnImageRects[range.location] = imageRect

        // Draw delete button when this image is hovered
        if hoveredImageCharIndex == range.location {
            drawDeleteButton(in: imageRect, charIndex: range.location)
        }
    }

    /// Draws a semi-transparent circular delete button at the top-right corner of the image rect.
    private func drawDeleteButton(in imageRect: NSRect, charIndex: Int) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let buttonSize: CGFloat = 20
        let padding: CGFloat = 6
        let buttonRect = NSRect(
            x: imageRect.maxX - buttonSize - padding,
            y: imageRect.minY + padding,
            width: buttonSize,
            height: buttonSize
        )

        // Draw semi-transparent black circle background
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.fillEllipse(in: buttonRect)
        ctx.restoreGState()

        // Draw white xmark SF Symbol
        let symbolSize: CGFloat = 10
        let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
        if let xmarkImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let tinted = xmarkImage.tinted(with: .white)
            let symbolSize = tinted.size
            let symbolX = buttonRect.midX - symbolSize.width / 2
            let symbolY = buttonRect.midY - symbolSize.height / 2
            tinted.draw(in: NSRect(x: symbolX, y: symbolY, width: symbolSize.width, height: symbolSize.height))
        }

        drawnDeleteButtonRects[charIndex] = buttonRect
    }

    /// Draws an SF Symbol at the actual glyph position (for inline elements).
    private func drawSFSymbolAtGlyphPosition(_ name: String, at range: NSRange, origin: NSPoint, color: NSColor, size: CGFloat) {
        let glyphIndex = glyphIndexForCharacter(at: range.location)
        guard textContainer(forGlyphAt: glyphIndex, effectiveRange: nil) != nil else { return }
        let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let glyphLocation = location(forGlyphAt: glyphIndex)
        let baselineY = origin.y + lineRect.origin.y + baselineOffset(forGlyphAt: glyphIndex, fontSize: size)

        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }

        let tinted = image.tinted(with: color)
        let imageSize = tinted.size
        let x = origin.x + lineRect.origin.x + glyphLocation.x
        let textFont = referenceFont(size: size)
        let textCenterY = baselineY - textFont.capHeight / 2
        let y = textCenterY - imageSize.height / 2
        tinted.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height))
    }

    private func clearDrawnRects(_ dict: inout [Int: NSRect], in range: NSRange) {
        dict = dict.filter { $0.key < range.location || $0.key >= range.location + range.length }
    }

    /// Draws a "…" badge at the end of a folded line's visible content.
    private func drawFoldEllipsis(at range: NSRange, origin: NSPoint) {
        let glyphIndex = glyphIndexForCharacter(at: range.location)
        guard textContainer(forGlyphAt: glyphIndex, effectiveRange: nil) != nil else { return }

        let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let usedRect = lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)

        let font = referenceFont(size: baseFontSize * 0.85)
        let textColor = NSColor.secondaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let ellipsis = "…" as NSString
        let textSize = ellipsis.size(withAttributes: attrs)

        let hPadding: CGFloat = 4
        let gap: CGFloat = 4
        let textX = origin.x + usedRect.maxX + gap + hPadding
        let textY = origin.y + lineRect.midY - textSize.height / 2

        // Draw rounded background
        let bgRect = NSRect(
            x: textX - hPadding,
            y: textY - 1,
            width: textSize.width + hPadding * 2,
            height: textSize.height + 2
        )
        NoteColor.codeBackgroundColor.setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()

        // Draw ellipsis text
        ellipsis.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

        // Record rect for hit-testing (keyed by character index for range-scoped clearing)
        drawnEllipsisRects[range.location] = bgRect
    }

    private func drawSymbol(_ symbol: String, at range: NSRange, origin: NSPoint, color: NSColor, fontSize: CGFloat) {
        guard let pos = glyphPosition(at: range, origin: origin, fontSize: fontSize) else { return }

        let font = referenceFont(size: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let x = origin.x + pos.lineRect.origin.x + 5 + CGFloat(pos.level) * 20
        let y = pos.baselineY - font.ascender
        symbol.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage // swiftlint:disable:this force_cast
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}

// MARK: - NSLayoutManagerDelegate

extension BulletLayoutManager: NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        guard let textStorage = textStorage else { return false }
        let charRange = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard charRange.length > 0 else { return false }

        let shouldCollapse =
            textStorage.attribute(.tableSeparatorRow, at: charRange.location, effectiveRange: nil) != nil ||
            textStorage.attribute(.foldedContent, at: charRange.location, effectiveRange: nil) != nil
        guard shouldCollapse else { return false }

        lineFragmentRect.pointee.size.height = 0.01
        lineFragmentUsedRect.pointee.size.height = 0.01
        baselineOffset.pointee = 0
        return true
    }
}
