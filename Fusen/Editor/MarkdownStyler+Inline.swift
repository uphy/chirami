import AppKit

// MARK: - Inline style patterns (bold, italic, strikethrough, inline code, links)

extension MarkdownStyler {

    static let boldPattern = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*|__(.+?)__"#)
    static let italicPattern = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#)
    static let strikethroughPattern = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
    static let inlineCodePattern = try! NSRegularExpression(pattern: #"`(.+?)`"#)
    // Negative lookbehind (?<!!) prevents matching image syntax ![alt](url)
    static let linkPattern = try! NSRegularExpression(pattern: #"(?<!!)\[(.+?)\]\((.+?)\)"#)
    static let imagePattern = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^\)]+)\)"#)

    // MARK: - Rendered inline styles

    func applyInlineStyles(to storage: NSMutableAttributedString, range: NSRange, in text: String) {
        let substring = (text as NSString).substring(with: range)
        applyInlinePatterns(to: storage, in: substring, offset: range.location)
    }

    func applyInlinePatterns(to storage: NSMutableAttributedString, in text: String, offset: Int) {
        applyPattern(Self.boldPattern, to: storage, in: text, offset: offset,
                     attributes: [.font: NSFont.systemFont(ofSize: baseFontSize, weight: .bold)],
                     hideMarkers: true, markerLength: 2)

        applyPattern(Self.italicPattern, to: storage, in: text, offset: offset,
                     attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: baseFontSize), toHaveTrait: .italicFontMask)],
                     hideMarkers: true, markerLength: 1)

        applyPattern(Self.strikethroughPattern, to: storage, in: text, offset: offset,
                     attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue],
                     hideMarkers: true, markerLength: 2)

        applyPattern(Self.inlineCodePattern, to: storage, in: text, offset: offset,
                     attributes: [
                         .font: NSFont.monospacedSystemFont(ofSize: baseFontSize - 1, weight: .regular),
                         .foregroundColor: NSColor.systemOrange,
                         .inlineCodeBackground: NSColor.labelColor.withAlphaComponent(0.08)
                     ],
                     hideMarkers: true, markerLength: 1)

        applyLinkPattern(to: storage, in: text, offset: offset)
        applyImagePattern(to: storage, in: text, offset: offset)
    }

    // MARK: - Raw (editing) inline styles

    func applyRawInlinePatterns(to storage: NSMutableAttributedString, in text: String, offset: Int) {
        applyRawPattern(Self.boldPattern, to: storage, in: text, offset: offset,
                        contentAttributes: [.font: NSFont.systemFont(ofSize: baseFontSize, weight: .bold), .foregroundColor: noteColor.textColor])

        applyRawPattern(Self.italicPattern, to: storage, in: text, offset: offset,
                        contentAttributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: baseFontSize), toHaveTrait: .italicFontMask), .foregroundColor: noteColor.textColor])

        applyRawPattern(Self.strikethroughPattern, to: storage, in: text, offset: offset,
                        contentAttributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: noteColor.textColor])

        applyRawPattern(Self.inlineCodePattern, to: storage, in: text, offset: offset,
                        contentAttributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: baseFontSize - 1, weight: .regular),
                            .foregroundColor: NSColor.systemOrange,
                            .inlineCodeBackground: NSColor.labelColor.withAlphaComponent(0.08)
                        ])

        applyRawLinkPattern(to: storage, in: text, offset: offset)
        applyRawImagePattern(to: storage, in: text, offset: offset)
    }

    // MARK: - Pattern application helpers

    private func applyPattern(
        _ regex: NSRegularExpression,
        to storage: NSMutableAttributedString,
        in text: String,
        offset: Int,
        attributes: [NSAttributedString.Key: Any],
        hideMarkers: Bool,
        markerLength: Int
    ) {
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            storage.addAttributes(attributes, range: fullRange)

            if hideMarkers {
                let openRange = NSRange(location: fullRange.location, length: markerLength)
                storage.addAttributes(Self.hiddenAttributes, range: openRange)

                let closeRange = NSRange(location: fullRange.location + fullRange.length - markerLength, length: markerLength)
                storage.addAttributes(Self.hiddenAttributes, range: closeRange)
            }
        }
    }

    private func applyRawPattern(
        _ regex: NSRegularExpression,
        to storage: NSMutableAttributedString,
        in text: String,
        offset: Int,
        contentAttributes: [NSAttributedString.Key: Any],
        markerColor: NSColor = .secondaryLabelColor
    ) {
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)

            // Find the first non-empty capture group (content without markers)
            var contentAdjustedRange: NSRange? = nil
            for groupIdx in 1..<match.numberOfRanges {
                let contentRange = match.range(at: groupIdx)
                if contentRange.location != NSNotFound {
                    contentAdjustedRange = NSRange(location: contentRange.location + offset, length: contentRange.length)
                    break
                }
            }

            if let contentRange = contentAdjustedRange {
                // Gray the opening marker (before content)
                let openLen = contentRange.location - fullRange.location
                if openLen > 0 {
                    let openRange = NSRange(location: fullRange.location, length: openLen)
                    storage.addAttributes([.foregroundColor: markerColor], range: openRange)
                }
                // Gray the closing marker (after content)
                let closeStart = contentRange.location + contentRange.length
                let closeLen = (fullRange.location + fullRange.length) - closeStart
                if closeLen > 0 {
                    let closeRange = NSRange(location: closeStart, length: closeLen)
                    storage.addAttributes([.foregroundColor: markerColor], range: closeRange)
                }
                // Apply content attributes
                storage.addAttributes(contentAttributes, range: contentRange)
            } else {
                // No capture group found -- gray entire match
                storage.addAttributes([.foregroundColor: markerColor], range: fullRange)
            }
        }
    }

    private func applyLinkPattern(to storage: NSMutableAttributedString, in text: String, offset: Int) {
        let regex = Self.linkPattern
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            let urlRange = match.range(at: 2)
            if urlRange.location != NSNotFound {
                let urlStr = nsText.substring(with: urlRange)
                if let url = URL(string: urlStr) {
                    storage.addAttributes([
                        .link: url,
                        .foregroundColor: noteColor.linkColor
                    ], range: fullRange)
                }
            }

            // Hide the markdown syntax for the link wrapper: [, ](url)
            // Show only the link text
            let textRange = match.range(at: 1)
            if textRange.location != NSNotFound {
                let openBracket = NSRange(location: fullRange.location, length: 1)
                storage.addAttributes(Self.hiddenAttributes, range: openBracket)

                let afterText = NSRange(
                    location: fullRange.location + 1 + textRange.length,
                    length: fullRange.length - 1 - textRange.length
                )
                storage.addAttributes(Self.hiddenAttributes, range: afterText)
            }
        }
    }

    private func applyRawLinkPattern(to storage: NSMutableAttributedString, in text: String, offset: Int) {
        let regex = Self.linkPattern
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: fullRange)

            let textRange = match.range(at: 1)
            if textRange.location != NSNotFound {
                let adjustedRange = NSRange(location: textRange.location + offset, length: textRange.length)
                storage.addAttributes([.foregroundColor: noteColor.linkColor], range: adjustedRange)
            }
        }
    }

    // MARK: - Image pattern (rendered)

    private func applyImagePattern(to storage: NSMutableAttributedString, in text: String, offset: Int) {
        let nsText = text as NSString
        let matches = Self.imagePattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            let urlRange = match.range(at: 2)
            guard urlRange.location != NSNotFound else { continue }
            let urlString = nsText.substring(with: urlRange)

            // Hide entire `![alt](url)` — image is drawn by BulletLayoutManager
            storage.addAttributes(Self.hiddenAttributes, range: fullRange)

            // Mark `!` with the image URL so BulletLayoutManager can look it up
            let bangRange = NSRange(location: fullRange.location, length: 1)
            storage.addAttribute(.imageIcon, value: urlString as NSString, range: bangRange)

            // Reserve vertical space for the image via paragraph minimumLineHeight
            let paraRange = (storage.string as NSString).paragraphRange(for: fullRange)
            let imageHeight = scaledImageHeight(for: urlString)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 0
            style.minimumLineHeight = imageHeight
            storage.addAttribute(.paragraphStyle, value: style, range: paraRange)

            // Trigger async load if the image is not yet cached
            let onReload = onImageLoaded
            ImageCache.shared.load(urlString) { onReload?() }
        }
    }

    /// Returns the display height for `urlString` given the current container width.
    /// Uses a placeholder if the image is not yet cached.
    private func scaledImageHeight(for urlString: String) -> CGFloat {
        guard let image = ImageCache.shared.image(for: urlString) else {
            return 100  // placeholder height while loading
        }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return 100 }
        let maxWidth = max(containerWidth - 20, 50)
        let maxHeight: CGFloat = 400
        let scale = min(maxWidth / size.width, maxHeight / size.height)
        return (size.height * scale).rounded()
    }

    // MARK: - Image pattern (raw/editing)

    private func applyRawImagePattern(to storage: NSMutableAttributedString, in text: String, offset: Int) {
        let nsText = text as NSString
        let matches = Self.imagePattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: fullRange)

            let altRange = match.range(at: 1)
            if altRange.location != NSNotFound && altRange.length > 0 {
                let adjustedAlt = NSRange(location: altRange.location + offset, length: altRange.length)
                storage.addAttributes([.foregroundColor: noteColor.linkColor], range: adjustedAlt)
            }
        }
    }
}
