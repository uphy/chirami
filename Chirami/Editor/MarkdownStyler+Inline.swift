import AppKit

// MARK: - Inline style patterns (bold, italic, strikethrough, inline code, links)

extension MarkdownStyler {

    // swiftlint:disable force_try
    static let boldPattern = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*|__(.+?)__"#)
    static let italicPattern = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#)
    static let strikethroughPattern = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
    static let inlineCodePattern = try! NSRegularExpression(pattern: #"`(.+?)`"#)
    // Negative lookbehind (?<!!) prevents matching image syntax ![alt](url)
    static let linkPattern = try! NSRegularExpression(pattern: #"(?<!!)\[(.+?)\]\((.+?)\)"#)
    static let imagePattern = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^\)]+)\)"#)
    // swiftlint:enable force_try

    // MARK: - Rendered inline styles

    func applyInlineStyles(to storage: NSMutableAttributedString, range: NSRange, in text: String, fontSize: CGFloat? = nil) {
        let substring = (text as NSString).substring(with: range)
        applyInlinePatterns(to: storage, in: substring, offset: range.location, fontSize: fontSize)
    }

    func applyInlinePatterns(to storage: NSMutableAttributedString, in text: String, offset: Int, cursorLocation: Int? = nil, fontSize: CGFloat? = nil) {
        let size = fontSize ?? baseFontSize

        applyPattern(Self.boldPattern, to: storage, in: text, offset: offset,
                     attributes: [.font: boldFont(size: size)],
                     hideMarkers: true, markerLength: 2)

        applyPattern(Self.italicPattern, to: storage, in: text, offset: offset,
                     attributes: [.font: italicFont(size: size)],
                     hideMarkers: true, markerLength: 1)

        applyPattern(Self.strikethroughPattern, to: storage, in: text, offset: offset,
                     attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue],
                     hideMarkers: true, markerLength: 2)

        applyPattern(Self.inlineCodePattern, to: storage, in: text, offset: offset,
                     attributes: InlineMarkupRenderer.inlineCodeAttributes(fontSize: size, fontName: fontName),
                     hideMarkers: true, markerLength: 1)

        applyLinkPattern(to: storage, in: text, offset: offset, cursorLocation: cursorLocation)
        applyImagePattern(to: storage, in: text, offset: offset)
    }

    // MARK: - Raw (editing) inline styles

    func applyRawInlinePatterns(to storage: NSMutableAttributedString, in text: String, offset: Int, cursorLocation: Int? = nil) {
        applyRawPattern(Self.boldPattern, to: storage, in: text, offset: offset,
                        contentAttributes: [.font: boldFont(size: baseFontSize), .foregroundColor: noteColor.textColor])

        applyRawPattern(Self.italicPattern, to: storage, in: text, offset: offset,
                        contentAttributes: [.font: italicFont(size: baseFontSize), .foregroundColor: noteColor.textColor])

        applyRawPattern(Self.strikethroughPattern, to: storage, in: text, offset: offset,
                        contentAttributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: noteColor.textColor])

        applyRawPattern(Self.inlineCodePattern, to: storage, in: text, offset: offset,
                        contentAttributes: InlineMarkupRenderer.inlineCodeAttributes(fontSize: baseFontSize, fontName: fontName))

        applyLinkPattern(to: storage, in: text, offset: offset, cursorLocation: cursorLocation)
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
            var contentAdjustedRange: NSRange?
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

    private func applyLinkPattern(to storage: NSMutableAttributedString, in text: String, offset: Int, cursorLocation: Int? = nil) {
        let regex = Self.linkPattern
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            let cursorInLink = cursorLocation.map { NSLocationInRange($0, fullRange) } ?? false

            if cursorInLink {
                // Raw styling: gray the entire match, then highlight text portion with link color
                storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: fullRange)
                let textRange = match.range(at: 1)
                if textRange.location != NSNotFound {
                    let adjustedRange = NSRange(location: textRange.location + offset, length: textRange.length)
                    storage.addAttributes([.foregroundColor: noteColor.linkColor], range: adjustedRange)
                }
            } else {
                // Rendered styling: apply link and hide syntax
                let textRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                if textRange.location != NSNotFound, urlRange.location != NSNotFound {
                    let urlStr = nsText.substring(with: urlRange)
                    if let url = URL(string: urlStr) {
                        let adjustedTextRange = NSRange(location: textRange.location + offset, length: textRange.length)
                        // Apply .link only to visible text to prevent underline extending to line start
                        storage.addAttributes([
                            .link: url,
                            .foregroundColor: noteColor.linkColor
                        ], range: adjustedTextRange)
                    }

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
    }

    // MARK: - Image width parsing

    /// Parses the requested display width from an image alt text containing `|width`.
    /// Returns nil for missing, non-numeric, zero, or negative values.
    /// For multiple pipes (e.g. `a|b|300`), the last segment is used.
    static func parseImageWidth(from altText: String) -> CGFloat? {
        guard let pipeIndex = altText.lastIndex(of: "|") else { return nil }
        let widthStr = String(altText[altText.index(after: pipeIndex)...]).trimmingCharacters(in: .whitespaces)
        guard let value = Double(widthStr), value > 0 else { return nil }
        return CGFloat(value)
    }

    // MARK: - Image pattern (rendered)

    /// Resolves a potentially relative image path to an absolute path using noteBaseURL.
    func resolveImagePath(_ path: String) -> String {
        // HTTP URLs: keep as-is
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        // Absolute paths: keep as-is
        if path.hasPrefix("/") { return path }
        // Tilde paths: keep as-is (ImageCache handles expansion)
        if path.hasPrefix("~/") { return path }
        // Relative path: resolve from noteBaseURL
        guard let baseURL = noteBaseURL else { return path }
        return baseURL.appendingPathComponent(path).standardizedFileURL.path
    }

    private func applyImagePattern(to storage: NSMutableAttributedString, in text: String, offset: Int) {
        let nsText = text as NSString
        let matches = Self.imagePattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            let altRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            guard urlRange.location != NSNotFound else { continue }
            let rawUrlString = nsText.substring(with: urlRange)
            let urlString = resolveImagePath(rawUrlString)

            // Parse requested width from alt text (e.g. `photo|200`)
            let altText = altRange.location != NSNotFound ? nsText.substring(with: altRange) : ""
            let requestedWidth = Self.parseImageWidth(from: altText)

            // Hide entire `![alt](url)` — image is drawn by BulletLayoutManager
            storage.addAttributes(Self.hiddenAttributes, range: fullRange)

            // Mark `!` with the image URL so BulletLayoutManager can look it up
            let bangRange = NSRange(location: fullRange.location, length: 1)
            storage.addAttribute(.imageIcon, value: urlString as NSString, range: bangRange)

            // Attach requested width if specified
            if let requestedWidth = requestedWidth {
                storage.addAttribute(.imageWidth, value: NSNumber(value: Double(requestedWidth)), range: bangRange)
            }

            // Reserve vertical space for the image via paragraph minimumLineHeight
            let paraRange = (storage.string as NSString).paragraphRange(for: fullRange)
            let imageHeight = scaledImageHeight(for: urlString, requestedWidth: requestedWidth)
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
    /// When `requestedWidth` is specified, scales to that width (clamped to container) without a height cap.
    /// When no width is specified, scales to fill the container with a maxHeight=400 cap.
    /// Uses a placeholder if the image is not yet cached.
    private func scaledImageHeight(for urlString: String, requestedWidth: CGFloat? = nil) -> CGFloat {
        guard let image = ImageCache.shared.image(for: urlString) else {
            return 100  // placeholder height while loading
        }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return 100 }
        let maxWidth = max(containerWidth - 20, 50)
        if let requested = requestedWidth {
            // Honor the explicit width; derive height from aspect ratio (no maxHeight cap)
            let displayWidth = min(requested, maxWidth)
            let scale = displayWidth / size.width
            return (size.height * scale).rounded()
        } else {
            let maxHeight: CGFloat = 400
            let scale = min(maxWidth / size.width, maxHeight / size.height)
            return (size.height * scale).rounded()
        }
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
