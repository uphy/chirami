import AppKit
import Highlightr

// MARK: - Code block styling with syntax highlighting

extension MarkdownStyler {

    static let highlightr: Highlightr? = {
        let h = Highlightr()
        return h
    }()

    var highlightThemeName: String {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? "github-dark" : "github"
    }

    static let codeBlockVerticalPadding: CGFloat = 6

    func applyCodeBlockStyle(to storage: NSMutableAttributedString, range: NSRange, text: String, language: String? = nil) {
        let horizontalPadding: CGFloat = 8
        let verticalPadding = Self.codeBlockVerticalPadding

        // Mark entire range for custom background drawing by BulletLayoutManager
        storage.addAttributes([
            .codeBlockBackground: NoteColor.codeBackgroundColor
        ], range: range)

        let nsText = text as NSString
        let substring = nsText.substring(with: range)
        let lines = substring.components(separatedBy: "\n")

        let monoFont = self.monoFont(size: (baseFontSize * 0.86).rounded())

        // Collect code body lines (excluding fence lines) for syntax highlighting
        var codeLines: [(text: String, offset: Int, length: Int)] = []
        var tempOffset = range.location
        for line in lines {
            let lineLen = (line as NSString).length
            if !line.hasPrefix("```") {
                codeLines.append((text: line, offset: tempOffset, length: lineLen))
            }
            tempOffset += lineLen + 1
        }

        // Attempt syntax highlighting with Highlightr
        let highlightColors = syntaxHighlightColors(for: codeLines, language: language)

        enumerateLines(in: text, range: range) { line, lineStart, isFirst, isLast in
            let lineLen = (line as NSString).length

            // Build per-line paragraph style (first/last lines get vertical padding)
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.headIndent = horizontalPadding
            paraStyle.firstLineHeadIndent = horizontalPadding
            paraStyle.tailIndent = -horizontalPadding
            if isFirst { paraStyle.paragraphSpacingBefore = verticalPadding }
            if isLast { paraStyle.paragraphSpacing = verticalPadding }

            // Apply paragraph style to the line (including its trailing newline)
            let fullLineLen = isLast ? lineLen : lineLen + 1
            if fullLineLen > 0 {
                storage.addAttributes([.paragraphStyle: paraStyle],
                                      range: NSRange(location: lineStart, length: fullLineLen))
            }

            if line.hasPrefix("```") {
                if lineLen > 0 {
                    storage.addAttributes(Self.hiddenAttributes,
                                          range: NSRange(location: lineStart, length: lineLen))
                }
                if !isLast {
                    storage.addAttributes(Self.hiddenAttributes,
                                          range: NSRange(location: lineStart + lineLen, length: 1))
                }
            } else if lineLen > 0 {
                let lineRange = NSRange(location: lineStart, length: lineLen)
                storage.addAttributes([.font: monoFont], range: lineRange)
                if highlightColors == nil {
                    storage.addAttributes([.foregroundColor: noteColor.codeColor], range: lineRange)
                }
            }
        }

        // Apply syntax highlight colors on top
        if let colors = highlightColors {
            for entry in colors {
                let colorRange = NSRange(location: entry.offset, length: entry.length)
                storage.addAttributes([.foregroundColor: entry.color], range: colorRange)
            }
        }
    }

    // MARK: - Syntax highlight color extraction

    private func syntaxHighlightColors(
        for codeLines: [(text: String, offset: Int, length: Int)],
        language: String?
    ) -> [(offset: Int, length: Int, color: NSColor)]? {
        guard let lang = language, !lang.isEmpty, !codeLines.isEmpty else { return nil }

        let codeBody = codeLines.map(\.text).joined(separator: "\n")
        guard let highlightr = Self.highlightr else { return nil }

        highlightr.setTheme(to: highlightThemeName)
        guard let highlighted = highlightr.highlight(codeBody, as: lang, fastRender: false) else { return nil }

        var colors: [(offset: Int, length: Int, color: NSColor)] = []
        let fullRange = NSRange(location: 0, length: highlighted.length)
        var hlOffset = 0

        for (lineIdx, codeLine) in codeLines.enumerated() {
            let lineStartInHighlighted = hlOffset
            let lineLen = (codeLine.text as NSString).length
            let hlLineRange = NSRange(location: lineStartInHighlighted, length: lineLen)

            if NSIntersectionRange(hlLineRange, fullRange).length > 0 {
                highlighted.enumerateAttribute(.foregroundColor, in: hlLineRange) { value, attrRange, _ in
                    if let color = value as? NSColor {
                        let storageOffset = codeLine.offset + (attrRange.location - lineStartInHighlighted)
                        colors.append((offset: storageOffset, length: attrRange.length, color: color))
                    }
                }
            }
            hlOffset += lineLen + (lineIdx < codeLines.count - 1 ? 1 : 0)
        }

        return colors.isEmpty ? nil : colors
    }
}
