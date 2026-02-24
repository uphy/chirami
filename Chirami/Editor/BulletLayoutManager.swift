import AppKit

/// Custom layout manager that draws bullet points (•) over hidden unordered list markers.
class BulletLayoutManager: NSLayoutManager {

    var baseFontSize: CGFloat = 14

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
            let glyphRange = glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            var lineRect = NSRect.zero
            enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
                lineRect = rect
            }
            guard lineRect != .zero else { return }
            let y = (origin.y + lineRect.midY).rounded() - 0.5
            NSColor.separatorColor.setFill()
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

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        // Draw bullet markers (•)
        textStorage.enumerateAttribute(.bulletMarker, in: charRange, options: []) { value, range, _ in
            guard value != nil else { return }
            drawSymbol("•", at: range, origin: origin, color: NSColor.secondaryLabelColor, fontSize: baseFontSize)
        }

        // Draw task checkboxes using SF Symbols
        textStorage.enumerateAttribute(.taskCheckbox, in: charRange, options: []) { value, range, _ in
            guard let number = value as? NSNumber else { return }
            let checked = number.boolValue
            let symbolName = checked ? "checkmark.square.fill" : "square"
            let color = checked ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
            drawSFSymbol(symbolName, at: range, origin: origin, color: color, size: baseFontSize)
        }

        // Draw inline images (or a placeholder icon while loading)
        textStorage.enumerateAttribute(.imageIcon, in: charRange, options: []) { value, range, _ in
            guard let urlString = value as? String else { return }
            if let image = ImageCache.shared.image(for: urlString) {
                drawInlineImage(image, at: range, origin: origin)
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
    private func baselineOffset(forGlyphAt glyphIndex: Int, fontSize: CGFloat) -> CGFloat {
        let referenceFont = NSFont.systemFont(ofSize: fontSize)
        // minimumLineHeight matches applyListParagraphStyle: ceil(ascender - descender + leading)
        // baseline = minimumLineHeight + descender
        return ceil(referenceFont.ascender - referenceFont.descender + referenceFont.leading) + referenceFont.descender
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
        let baselineY = origin.y + lineRect.origin.y + baselineOffset(forGlyphAt: glyphIndex, fontSize: fontSize)
        return GlyphPosition(glyphIndex: glyphIndex, lineRect: lineRect, level: level, baselineY: baselineY)
    }

    private func drawSFSymbol(_ name: String, at range: NSRange, origin: NSPoint, color: NSColor, size: CGFloat) {
        guard let pos = glyphPosition(at: range, origin: origin, fontSize: size) else { return }

        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }

        let tinted = image.tinted(with: color)
        let imageSize = tinted.size
        let x = origin.x + pos.lineRect.origin.x + 2 + CGFloat(pos.level) * 20
        let textFont = NSFont.systemFont(ofSize: size)
        let textCenterY = pos.baselineY - textFont.capHeight / 2
        let y = textCenterY - imageSize.height / 2
        tinted.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height))
    }

    /// Draws a loaded image inline at the glyph position of the `!` marker character.
    /// Scales the image to fit the line fragment height while capping at the container width.
    private func drawInlineImage(_ image: NSImage, at range: NSRange, origin: NSPoint) {
        let glyphIndex = glyphIndexForCharacter(at: range.location)
        guard textContainer(forGlyphAt: glyphIndex, effectiveRange: nil) != nil else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let glyphLocation = location(forGlyphAt: glyphIndex)
        let availableWidth = (textContainers.first?.size.width ?? 380) - glyphLocation.x - 16

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scale = min(availableWidth / imageSize.width, lineRect.height / imageSize.height)
        let drawWidth = (imageSize.width * scale).rounded()
        let drawHeight = (imageSize.height * scale).rounded()

        let x = origin.x + lineRect.origin.x + glyphLocation.x
        let y = origin.y + lineRect.origin.y + ((lineRect.height - drawHeight) / 2).rounded()

        // NSTextView is flipped (y increases downward). CGContext.draw(cgImage:in:) assumes
        // unflipped coordinates (y increases upward). Apply an explicit flip so the image
        // appears right-side up: translate to the image's bottom-left in the flipped view,
        // then negate the y-axis so CGContext's "up" maps to the screen's "up".
        ctx.saveGState()
        ctx.translateBy(x: x, y: y + drawHeight)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: drawWidth, height: drawHeight))
        ctx.restoreGState()
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
        let textFont = NSFont.systemFont(ofSize: size)
        let textCenterY = baselineY - textFont.capHeight / 2
        let y = textCenterY - imageSize.height / 2
        tinted.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height))
    }

    private func drawSymbol(_ symbol: String, at range: NSRange, origin: NSPoint, color: NSColor, fontSize: CGFloat) {
        guard let pos = glyphPosition(at: range, origin: origin, fontSize: fontSize) else { return }

        let font = NSFont.systemFont(ofSize: fontSize)
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
        guard charRange.length > 0,
              textStorage.attribute(.tableSeparatorRow, at: charRange.location, effectiveRange: nil) != nil
        else { return false }

        lineFragmentRect.pointee.size.height = 0.01
        lineFragmentUsedRect.pointee.size.height = 0.01
        baselineOffset.pointee = 0
        return true
    }
}
