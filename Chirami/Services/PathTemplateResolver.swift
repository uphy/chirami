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

    /// Converts template placeholders to glob wildcards ({...} → *).
    static func toGlobPattern(_ template: String) -> String {
        let nsString = template as NSString
        let range = NSRange(location: 0, length: nsString.length)
        return placeholderRegex.stringByReplacingMatches(in: template, range: range, withTemplate: "*")
    }

    /// Returns true if the relative path matches the template's date format.
    static func matches(relativePath: String, template: String) -> Bool {
        let baseDir = extractBaseDirectory(from: template)
        let relativeTemplate = String(template.dropFirst(baseDir.count))

        // Build a DateFormatter format string from the relative template.
        // {format} → kept as-is, static parts → escaped with single quotes
        var combinedFormat = ""
        var index = relativeTemplate.startIndex
        while index < relativeTemplate.endIndex {
            if relativeTemplate[index] == "{" {
                if let endBrace = relativeTemplate[index...].firstIndex(of: "}") {
                    let formatStart = relativeTemplate.index(after: index)
                    combinedFormat += String(relativeTemplate[formatStart..<endBrace])
                    index = relativeTemplate.index(after: endBrace)
                } else {
                    break
                }
            } else {
                combinedFormat += "'"
                while index < relativeTemplate.endIndex && relativeTemplate[index] != "{" {
                    let ch = relativeTemplate[index]
                    if ch == "'" {
                        combinedFormat += "''"
                    } else {
                        combinedFormat += String(ch)
                    }
                    index = relativeTemplate.index(after: index)
                }
                combinedFormat += "'"
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = combinedFormat
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false

        guard let date = formatter.date(from: relativePath) else {
            return false
        }
        // Round-trip validation: reformat the parsed date to confirm it matches
        return formatter.string(from: date) == relativePath
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
