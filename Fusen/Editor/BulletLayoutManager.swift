import AppKit

/// Custom layout manager that draws bullet points (•) over hidden unordered list markers.
class BulletLayoutManager: NSLayoutManager {

    var baseFontSize: CGFloat = 14

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage,
              let textContainer = textContainers.first else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let containerWidth = textContainer.size.width

        textStorage.enumerateAttribute(.codeBlockBackground, in: charRange, options: []) { value, attrRange, _ in
            guard let color = value as? NSColor else { return }
            let glyphRange = glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)

            // Compute bounding rect of all line fragments in this code block
            var minY: CGFloat = .greatestFiniteMagnitude
            var maxY: CGFloat = 0
            enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                minY = min(minY, lineRect.origin.y)
                maxY = max(maxY, lineRect.origin.y + lineRect.height)
            }
            guard minY < maxY else { return }

            let bgRect = NSRect(
                x: origin.x,
                y: origin.y + minY,
                width: containerWidth,
                height: maxY - minY
            )
            color.setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6).fill()
        }

        // Block quote left border
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
            guard minY < maxY else { return }

            let borderWidth: CGFloat = 3
            let borderX: CGFloat = origin.x + 4
            let borderRect = NSRect(
                x: borderX,
                y: origin.y + minY,
                width: borderWidth,
                height: maxY - minY
            )
            color.setFill()
            NSBezierPath(roundedRect: borderRect, xRadius: borderWidth / 2, yRadius: borderWidth / 2).fill()
        }

        // Inline code backgrounds with rounded corners
        textStorage.enumerateAttribute(.inlineCodeBackground, in: charRange, options: []) { value, attrRange, _ in
            guard let color = value as? NSColor else { return }
            let glyphRange = glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            let rect = boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let bgRect = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -2, dy: -1)
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
    }

    /// Computes the baseline Y offset within the line fragment rect using a reference font.
    /// Hidden marker characters use a tiny font (0.001pt), which causes
    /// `self.location(forGlyphAt:)` to return an incorrect baseline for empty list items.
    /// Deriving the baseline from the line fragment height and reference font metrics
    /// gives a consistent position regardless of the actual glyph fonts.
    private func baselineOffset(forGlyphAt glyphIndex: Int, fontSize: CGFloat) -> CGFloat {
        let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let referenceFont = NSFont.systemFont(ofSize: fontSize)
        let paragraphStyle = textStorage?.attribute(
            .paragraphStyle,
            at: characterIndexForGlyph(at: glyphIndex),
            effectiveRange: nil
        ) as? NSParagraphStyle
        let lineSpacing = paragraphStyle?.lineSpacing ?? 0
        // baseline = (lineHeight - lineSpacing) + descender
        // descender is negative, so this positions the baseline correctly from the top
        return (lineRect.height - lineSpacing) + referenceFont.descender
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
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
