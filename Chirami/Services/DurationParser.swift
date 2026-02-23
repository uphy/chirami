import Foundation

enum DurationParser {
    private static let durationRegex = try! NSRegularExpression(pattern: "^(\\d+)(h|m)$")

    /// "2h" → 7200, "30m" → 1800, nil/"0"/不正値 → 0
    static func parse(_ string: String?) -> TimeInterval {
        guard let string, !string.isEmpty else { return 0 }
        if string == "0" { return 0 }

        let range = NSRange(string.startIndex..., in: string)
        guard let match = durationRegex.firstMatch(in: string, range: range),
              let valueRange = Range(match.range(at: 1), in: string),
              let unitRange = Range(match.range(at: 2), in: string),
              let value = Double(string[valueRange])
        else {
            return 0
        }

        let unit = String(string[unitRange])
        switch unit {
        case "h": return value * 3600
        case "m": return value * 60
        default: return 0
        }
    }
}
