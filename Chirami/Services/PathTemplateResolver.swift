import Foundation

enum PathTemplateResolver {
    // swiftlint:disable:next force_try
    private static let placeholderRegex = try! NSRegularExpression(pattern: "\\{([^}]+)\\}")

    /// Returns true if the path contains template placeholders.
    static func isTemplate(_ path: String) -> Bool {
        let range = NSRange(path.startIndex..., in: path)
        return placeholderRegex.firstMatch(in: path, range: range) != nil
    }

    /// Resolves template placeholders for the given date and returns the expanded path.
    static func resolve(_ template: String, for date: Date) -> String {
        let nsString = template as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = placeholderRegex.matches(in: template, range: range)

        var result = template
        // Replace from end to avoid index shifting
        for match in matches.reversed() {
            let fullRange = Range(match.range, in: template)!
            let formatRange = Range(match.range(at: 1), in: template)!
            let format = String(template[formatRange])

            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let replacement = formatter.string(from: date)

            result = result.replacingCharacters(in: fullRange, with: replacement)
        }
        return result
    }

    /// Resolves template placeholders for the given date (like `resolve`), then
    /// resolves any `*` wildcard — used only by stream-mode filename templates,
    /// e.g. `{yyyy-MM-dd-HHmmss}-*.md` — to the empty string.
    ///
    /// `resolve` itself is intentionally left untouched so periodic resolution
    /// stays byte-for-byte unchanged; periodic templates never contain `*`.
    static func resolveStream(_ template: String, for date: Date) -> String {
        resolve(template, for: date).replacingOccurrences(of: "*", with: "")
    }

    /// Converts template placeholders to glob wildcards ({...} → *).
    static func toGlobPattern(_ template: String) -> String {
        let nsString = template as NSString
        let range = NSRange(location: 0, length: nsString.length)
        return placeholderRegex.stringByReplacingMatches(in: template, range: range, withTemplate: "*")
    }

    /// Returns true if the relative path matches the template's date format.
    /// Stream templates may additionally contain a single `*` wildcard in the
    /// relative (filename) portion, matching zero or more characters.
    static func matches(relativePath: String, template: String) -> Bool {
        let baseDir = extractBaseDirectory(from: template)
        let relativeTemplate = String(template.dropFirst(baseDir.count))

        if relativeTemplate.contains("*") {
            return matchesWildcardTemplate(relativePath: relativePath, relativeTemplate: relativeTemplate)
        }

        return matchesFixedSegment(relativePath, template: relativeTemplate)
    }

    /// Matches `value` against a template segment made only of `{...}` date
    /// placeholders and literal characters (no `*`). This is the original
    /// periodic-note matching algorithm; it is also reused for the fixed
    /// prefix/suffix segments on either side of a stream `*` wildcard.
    private static func matchesFixedSegment(_ value: String, template: String) -> Bool {
        // Fast path: a template with no placeholder is a plain literal match.
        guard template.contains("{") else {
            return value == template
        }

        // Build a DateFormatter format string from the template segment.
        // {format} → kept as-is, static parts → escaped with single quotes
        var combinedFormat = ""
        var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{" {
                if let endBrace = template[index...].firstIndex(of: "}") {
                    let formatStart = template.index(after: index)
                    combinedFormat += String(template[formatStart..<endBrace])
                    index = template.index(after: endBrace)
                } else {
                    break
                }
            } else {
                combinedFormat += "'"
                while index < template.endIndex && template[index] != "{" {
                    let ch = template[index]
                    if ch == "'" {
                        combinedFormat += "''"
                    } else {
                        combinedFormat += String(ch)
                    }
                    index = template.index(after: index)
                }
                combinedFormat += "'"
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = combinedFormat
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false

        guard let date = formatter.date(from: value) else {
            return false
        }
        // Round-trip validation: reformat the parsed date to confirm it matches
        return formatter.string(from: date) == value
    }

    /// Matches `relativePath` against a stream template segment containing a
    /// single `*` wildcard. Tries every way of splitting `relativePath` into a
    /// fixed prefix, an arbitrary (possibly empty) middle section consumed by
    /// `*`, and a fixed suffix, checking the fixed parts with
    /// `matchesFixedSegment`. Filenames are short, so the O(n²) search is cheap.
    private static func matchesWildcardTemplate(relativePath: String, relativeTemplate: String) -> Bool {
        guard let wildcardIndex = relativeTemplate.firstIndex(of: "*") else { return false }
        let prefixTemplate = String(relativeTemplate[relativeTemplate.startIndex..<wildcardIndex])
        let suffixTemplate = String(relativeTemplate[relativeTemplate.index(after: wildcardIndex)...])

        let chars = Array(relativePath)
        for prefixEnd in 0...chars.count {
            guard matchesFixedSegment(String(chars[0..<prefixEnd]), template: prefixTemplate) else { continue }
            for suffixStart in prefixEnd...chars.count
            where matchesFixedSegment(String(chars[suffixStart...]), template: suffixTemplate) {
                return true
            }
        }
        return false
    }

    /// Returns the static directory prefix of the template (the part before the first {...}).
    static func extractBaseDirectory(from template: String) -> String {
        guard let firstBrace = template.firstIndex(of: "{") else {
            return template
        }
        let beforeBrace = template[template.startIndex..<firstBrace]
        if let lastSlash = beforeBrace.lastIndex(of: "/") {
            return String(template[template.startIndex...lastSlash])
        }
        return ""
    }
}
