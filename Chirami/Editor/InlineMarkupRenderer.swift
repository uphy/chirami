import AppKit
import Markdown

// MARK: - Shared inline styling constants and AST renderer

enum InlineMarkupRenderer {

    // MARK: - Centralized inline code styling

    static func inlineCodeAttributes(fontSize: CGFloat, fontName: String? = nil) -> [NSAttributedString.Key: Any] {
        let font: NSFont
        if let fontName, let customFont = NSFont(name: fontName, size: fontSize - 1) {
            font = customFont
        } else {
            font = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
        }
        return [
            .font: font,
            .foregroundColor: NSColor.codeGreen,
            .inlineCodeBackground: NSColor.codeBackground
        ]
    }

    // MARK: - AST → NSAttributedString

    /// Recursively builds an NSAttributedString from an inline AST node.
    static func attributedText(of node: any Markup, font: NSFont, noteColor: NoteColor) -> NSAttributedString {
        if let textNode = node as? Text {
            return NSAttributedString(string: textNode.string, attributes: [
                .font: font,
                .foregroundColor: noteColor.textColor
            ])
        }

        if node is SoftBreak || node is LineBreak {
            return NSAttributedString(string: " ", attributes: [
                .font: font,
                .foregroundColor: noteColor.textColor
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
            return NSAttributedString(string: code.code, attributes: inlineCodeAttributes(fontSize: font.pointSize))
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
}
