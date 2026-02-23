import Foundation

enum PathTemplateResolver {
    private static let placeholderRegex = try! NSRegularExpression(pattern: "\\{([^}]+)\\}")

    /// テンプレート文字列かどうかを判定
    static func isTemplate(_ path: String) -> Bool {
        let range = NSRange(path.startIndex..., in: path)
        return placeholderRegex.firstMatch(in: path, range: range) != nil
    }

    /// テンプレートを指定日付で解決し、展開済みパスを返す
    static func resolve(_ template: String, for date: Date) -> String {
        let nsString = template as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = placeholderRegex.matches(in: template, range: range)

        var result = template
        // 後ろから置換して位置ズレを防ぐ
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

    /// テンプレートを glob パターンに変換（{...} → *）
    static func toGlobPattern(_ template: String) -> String {
        let nsString = template as NSString
        let range = NSRange(location: 0, length: nsString.length)
        return placeholderRegex.stringByReplacingMatches(in: template, range: range, withTemplate: "*")
    }

    /// 相対パスがテンプレートのフォーマットにマッチするか判定
    static func matches(relativePath: String, template: String) -> Bool {
        let baseDir = extractBaseDirectory(from: template)
        let relativeTemplate = String(template.dropFirst(baseDir.count))

        // 相対テンプレートから DateFormatter フォーマット文字列を構築
        // {format} → そのまま、静的部分 → シングルクォートでエスケープ
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
        // Round-trip 検証: パースした日付を再フォーマットして一致するか確認
        return formatter.string(from: date) == relativePath
    }

    /// テンプレートの静的プレフィックス（{...} より前のディレクトリ部分）を返す
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
