import AppKit

enum ClipboardContentType {
    case html(String)
    case url(URL)
    case json(String)
    case code(String)
    case plainText(String)
}

struct SmartPasteResult {
    let markdown: String
    let pendingTitleFetch: URL?
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

        if isCode(trimmed) {
            return .code(trimmed)
        }

        return .plainText(text)
    }

    // MARK: - Conversion

    func convert(_ content: ClipboardContentType, fetchUrlTitle: Bool) -> SmartPasteResult {
        switch content {
        case .html(let html):
            return SmartPasteResult(markdown: convertHTMLToMarkdown(html), pendingTitleFetch: nil)
        case .url(let url):
            if fetchUrlTitle {
                return SmartPasteResult(
                    markdown: "[](\(url.absoluteString))",
                    pendingTitleFetch: url
                )
            } else {
                return SmartPasteResult(
                    markdown: "[\(url.absoluteString)](\(url.absoluteString))",
                    pendingTitleFetch: nil
                )
            }
        case .json(let json):
            return SmartPasteResult(markdown: wrapInCodeBlock(json, language: "json"), pendingTitleFetch: nil)
        case .code(let code):
            return SmartPasteResult(markdown: wrapInCodeBlock(code, language: nil), pendingTitleFetch: nil)
        case .plainText(let text):
            return SmartPasteResult(markdown: text, pendingTitleFetch: nil)
        }
    }

    // MARK: - URL title fetching

    func fetchTitle(for url: URL) async -> String? {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }
            return extractTitle(from: html)
        } catch {
            return nil
        }
    }

    // MARK: - Private helpers

    private func isURL(_ text: String) -> Bool {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
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

    private func isCode(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return false }

        let codeIndicators: [Character] = ["{", "}", ";", "(", ")"]
        let hasCodeChars = text.contains(where: { codeIndicators.contains($0) })

        let hasIndentation = lines.contains { line in
            line.hasPrefix("    ") || line.hasPrefix("\t")
        }

        return hasCodeChars || hasIndentation
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
            return convertElement(node as! XMLElement)
        default:
            return convertChildren(of: node)
        }
    }

    private func convertChildren(of node: XMLNode) -> String {
        (node.children ?? []).map { convertNode($0) }.joined()
    }

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
                   (subEl.name?.lowercased() == "ul" || subEl.name?.lowercased() == "ol") {
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
        var headerRowIndex: Int? = nil

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

    private func extractTitle(from html: String) -> String? {
        if let ogTitle = extractMetaContent(from: html, property: "og:title") {
            return ogTitle
        }
        if let titleRange = html.range(of: "<title>"),
           let endRange = html.range(of: "</title>") {
            let title = String(html[titleRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
        return nil
    }

    private func extractMetaContent(from html: String, property: String) -> String? {
        let patterns = [
            "property=\"\(property)\"\\s+content=\"([^\"]+)\"",
            "content=\"([^\"]+)\"\\s+property=\"\(property)\""
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) {
                if let range = Range(match.range(at: 1), in: html) {
                    let value = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
            }
        }
        return nil
    }
}
