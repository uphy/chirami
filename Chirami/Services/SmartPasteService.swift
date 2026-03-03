import AppKit

enum ClipboardContentType {
    case html(String)
    case url(URL)
    case json(String)
    case plainText(String)
}

struct SmartPasteResult {
    let markdown: String
    let cursorOffset: Int?
}

@MainActor
final class SmartPasteService {
    static let shared = SmartPasteService()

    private init() {}

    // MARK: - Content type detection

    func detectContentType() -> ClipboardContentType? {
        let pasteboard = NSPasteboard.general
        guard let types = pasteboard.types else { return nil }

        // Priority: HTML → URL → JSON → Code → Plain text
        if types.contains(.html),
           let htmlString = pasteboard.string(forType: .html),
           !htmlString.isEmpty {
            return .html(htmlString)
        }

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if isURL(trimmed) {
            return .url(URL(string: trimmed)!)
        }

        if isJSON(trimmed) {
            return .json(trimmed)
        }

        return .plainText(text)
    }

    // MARK: - Conversion

    func convert(_ content: ClipboardContentType, selectedText: String? = nil) -> SmartPasteResult {
        switch content {
        case .html(let html):
            return SmartPasteResult(markdown: convertHTMLToMarkdown(html), cursorOffset: nil)
        case .url(let url):
            if let selectedText, !selectedText.isEmpty {
                return SmartPasteResult(
                    markdown: "[\(selectedText)](\(url.absoluteString))",
                    cursorOffset: nil
                )
            }
            return SmartPasteResult(
                markdown: "[](\(url.absoluteString))",
                cursorOffset: 1
            )
        case .json(let json):
            return SmartPasteResult(markdown: wrapInCodeBlock(json, language: "json"), cursorOffset: nil)
        case .plainText(let text):
            return SmartPasteResult(markdown: text, cursorOffset: nil)
        }
    }

    // MARK: - Private helpers

    private func isURL(_ text: String) -> Bool {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return false
        }
        return !text.contains("\n")
    }

    private func isJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            return obj is [String: Any] || obj is [Any]
        } catch {
            return false
        }
    }

    // MARK: - HTML → Markdown (custom converter using XMLDocument)

    private func convertHTMLToMarkdown(_ html: String) -> String {
        guard let doc = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]) else {
            return NSPasteboard.general.string(forType: .string) ?? html
        }
        let markdown = convertNode(doc.rootElement())
        let normalized = markdown.replacingOccurrences(
            of: "\\n{3,}", with: "\n\n", options: .regularExpression
        )
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func convertNode(_ node: XMLNode?) -> String {
        guard let node = node else { return "" }
        switch node.kind {
        case .text:
            return node.stringValue ?? ""
        case .element:
            return convertElement(node as! XMLElement) // swiftlint:disable:this force_cast
        default:
            return convertChildren(of: node)
        }
    }

    private func convertChildren(of node: XMLNode) -> String {
        (node.children ?? []).map { convertNode($0) }.joined()
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func convertElement(_ el: XMLElement) -> String {
        let tag = el.name?.lowercased() ?? ""
        switch tag {
        case "h1": return "\n# \(inlineText(el))\n"
        case "h2": return "\n## \(inlineText(el))\n"
        case "h3": return "\n### \(inlineText(el))\n"
        case "h4": return "\n#### \(inlineText(el))\n"
        case "h5": return "\n##### \(inlineText(el))\n"
        case "h6": return "\n###### \(inlineText(el))\n"
        case "p":
            return "\n\(convertChildren(of: el))\n"
        case "br":
            return "\n"
        case "strong", "b":
            return "**\(convertChildren(of: el))**"
        case "em", "i":
            return "*\(convertChildren(of: el))*"
        case "code":
            if el.parent?.name?.lowercased() == "pre" {
                return convertChildren(of: el)
            }
            return "`\(convertChildren(of: el))`"
        case "pre":
            return "\n```\n\(convertChildren(of: el))\n```\n"
        case "a":
            let text = convertChildren(of: el)
            let href = el.attribute(forName: "href")?.stringValue ?? ""
            if href.isEmpty { return text }
            return "[\(text)](\(href))"
        case "img":
            let alt = el.attribute(forName: "alt")?.stringValue ?? ""
            let src = el.attribute(forName: "src")?.stringValue ?? ""
            return "![\(alt)](\(src))"
        case "ul":
            return convertList(el, ordered: false, depth: 0)
        case "ol":
            return convertList(el, ordered: true, depth: 0)
        case "blockquote":
            let inner = convertChildren(of: el).trimmingCharacters(in: .whitespacesAndNewlines)
            let quoted = inner.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
            return "\n\(quoted)\n"
        case "del", "s", "strike":
            return "~~\(convertChildren(of: el))~~"
        case "hr":
            return "\n---\n"
        case "table":
            return convertTable(el)
        case "thead", "tbody", "tfoot", "caption":
            return convertChildren(of: el)
        case "tr", "td", "th":
            return convertChildren(of: el)
        case "head", "meta", "style", "script", "link", "title":
            return ""
        default:
            return convertChildren(of: el)
        }
    }

    private func inlineText(_ el: XMLElement) -> String {
        convertChildren(of: el).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func convertList(_ el: XMLElement, ordered: Bool, depth: Int) -> String {
        var lines: [String] = []
        var index = 1
        let indent = String(repeating: "  ", count: depth)

        for child in el.children ?? [] {
            guard let childEl = child as? XMLElement,
                  childEl.name?.lowercased() == "li" else { continue }

            let marker = ordered ? "\(index)." : "-"
            var textParts: [String] = []
            var subListParts: [String] = []

            for sub in childEl.children ?? [] {
                if let subEl = sub as? XMLElement,
                   subEl.name?.lowercased() == "ul" || subEl.name?.lowercased() == "ol" {
                    let subOrdered = subEl.name?.lowercased() == "ol"
                    let subResult = convertList(subEl, ordered: subOrdered, depth: depth + 1)
                    subListParts.append(contentsOf: subResult.components(separatedBy: "\n").filter { !$0.isEmpty })
                } else {
                    textParts.append(convertNode(sub))
                }
            }

            let content = textParts.joined()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            lines.append("\(indent)\(marker) \(content)")
            lines.append(contentsOf: subListParts)
            index += 1
        }

        let joined = lines.joined(separator: "\n")
        return depth == 0 ? "\n\(joined)\n" : joined
    }

    private func convertTable(_ el: XMLElement) -> String {
        // Collect all <tr> rows regardless of thead/tbody structure
        guard let rows = try? el.nodes(forXPath: ".//tr") as? [XMLElement], !rows.isEmpty else {
            return convertChildren(of: el)
        }

        // Parse each row into cells
        var table: [[String]] = []
        var headerRowIndex: Int?

        for (rowIdx, row) in rows.enumerated() {
            var cells: [String] = []
            for child in row.children ?? [] {
                guard let cellEl = child as? XMLElement else { continue }
                let cellTag = cellEl.name?.lowercased() ?? ""
                guard cellTag == "td" || cellTag == "th" else { continue }
                let text = inlineText(cellEl)
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "|", with: "\\|")
                cells.append(text)
                if cellTag == "th" && headerRowIndex == nil {
                    headerRowIndex = rowIdx
                }
            }
            table.append(cells)
        }

        guard !table.isEmpty else { return "" }

        // Determine max column count
        let maxCols = table.map(\.count).max() ?? 0
        guard maxCols > 0 else { return "" }

        // Pad rows to maxCols
        for i in table.indices {
            while table[i].count < maxCols {
                table[i].append("")
            }
        }

        // First row is always the header (either actual <th> row or first <tr>)
        let headerIdx = headerRowIndex ?? 0
        var lines: [String] = []

        let headerLine = "| " + table[headerIdx].joined(separator: " | ") + " |"
        let separatorLine = "| " + Array(repeating: "---", count: maxCols).joined(separator: " | ") + " |"
        lines.append(headerLine)
        lines.append(separatorLine)

        for (idx, row) in table.enumerated() {
            if idx == headerIdx { continue }
            lines.append("| " + row.joined(separator: " | ") + " |")
        }

        return "\n" + lines.joined(separator: "\n") + "\n"
    }

    private func wrapInCodeBlock(_ text: String, language: String?) -> String {
        let lang = language ?? ""
        return "```\(lang)\n\(text)\n```"
    }

}
