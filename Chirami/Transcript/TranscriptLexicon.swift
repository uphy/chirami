import Foundation
import Yams

struct TranscriptLexiconTerm: Codable, Equatable, Sendable {
    let text: String
    let readings: [String]

    var sttValues: [String] {
        readings.isEmpty ? [text] : readings
    }
}

struct TranscriptLexicon: Equatable, Sendable {
    let version: Int
    let terms: [TranscriptLexiconTerm]

    var sttHotwords: [String] {
        var seen = Set<String>()
        var result: [String] = []

        for term in terms {
            for value in term.sttValues {
                let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidate.isEmpty, seen.insert(candidate).inserted else {
                    continue
                }
                result.append(candidate)
            }
        }

        return result
    }

    var hotwordsPayload: String? {
        let entries = sttHotwords.compactMap(Self.encodeHotword)
        guard !entries.isEmpty else {
            return nil
        }
        return entries.joined(separator: "/")
    }

    static func load(from url: URL) throws -> TranscriptLexicon {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        let raw = try YAMLDecoder().decode(RawTranscriptLexicon.self, from: yaml)

        guard raw.version == 1 else {
            throw TranscriptLexiconError.unsupportedVersion(raw.version)
        }

        var terms: [TranscriptLexiconTerm] = []
        var seenTexts = Set<String>()

        for rawTerm in raw.terms {
            let text = rawTerm.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty, seenTexts.insert(text).inserted else {
                continue
            }

            var seenReadings = Set<String>()
            let normalizedReadings = rawTerm.readings.compactMap { reading -> String? in
                let normalized = reading.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty, seenReadings.insert(normalized).inserted else {
                    return nil
                }
                return normalized
            }
            terms.append(TranscriptLexiconTerm(text: text, readings: normalizedReadings))
        }

        return TranscriptLexicon(version: raw.version, terms: terms)
    }

    private static func encodeHotword(_ value: String) -> String? {
        let tokens = value.filter { !$0.isWhitespace }.map(String.init)
        guard !tokens.isEmpty else { return nil }
        return tokens.joined(separator: " ")
    }
}

struct LoadedTranscriptLexicon: Equatable, Sendable {
    let url: URL
    let lexicon: TranscriptLexicon
}

enum TranscriptLexiconError: LocalizedError, Equatable {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Unsupported transcript lexicon version: \(version)"
        }
    }
}

func loadTranscriptLexicon(
    from transcriptConfig: TranscriptConfig,
    configDirectory: URL
) throws -> LoadedTranscriptLexicon? {
    guard let url = transcriptConfig.resolvedDictionaryFile(configDirectory: configDirectory) else {
        return nil
    }

    return LoadedTranscriptLexicon(
        url: url,
        lexicon: try TranscriptLexicon.load(from: url)
    )
}

private struct RawTranscriptLexicon: Decodable {
    let version: Int
    let terms: [RawTranscriptLexiconTerm]
}

private struct RawTranscriptLexiconTerm: Decodable {
    let text: String?
    let readings: [String]

    enum CodingKeys: String, CodingKey {
        case text
        case readings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        // `readings` accepts either a list of strings or a single scalar string.
        guard container.contains(.readings), try !container.decodeNil(forKey: .readings) else {
            readings = []
            return
        }
        do {
            readings = try container.decode([String].self, forKey: .readings)
        } catch DecodingError.typeMismatch {
            readings = [try container.decode(String.self, forKey: .readings)]
        }
    }
}
