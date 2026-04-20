import Foundation
import Testing
@testable import Chirami

@Suite("Transcript lexicon")
struct TranscriptLexiconTests {
    @Test("loads lexicon terms and keeps first text match")
    func loadsLexiconTerms() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lexiconURL = dir.appendingPathComponent("lexicon.yaml")
        try """
        version: 1
        terms:
          - text: uphy
            readings: [ユーピー, ユーピーさん, ユーピー]
          - text: OpenSpec
          - text: "  "
            readings: [ignored]
          - text: uphy
            readings: [duplicate]
          - text: Chirami
            readings: ""
        """.write(to: lexiconURL, atomically: true, encoding: .utf8)

        let lexicon = try TranscriptLexicon.load(from: lexiconURL)

        #expect(lexicon.version == 1)
        #expect(lexicon.terms == [
            TranscriptLexiconTerm(text: "uphy", readings: ["ユーピー", "ユーピーさん"]),
            TranscriptLexiconTerm(text: "OpenSpec", readings: []),
            TranscriptLexiconTerm(text: "Chirami", readings: [])
        ])
    }

    @Test("builds hotwords from readings before text")
    func buildsHotwordsFromReading() {
        let lexicon = TranscriptLexicon(
            version: 1,
            terms: [
                TranscriptLexiconTerm(text: "uphy", readings: ["ユーピー", "ユーピーさん"]),
                TranscriptLexiconTerm(text: "OpenSpec", readings: []),
                TranscriptLexiconTerm(text: "ignored", readings: ["ユーピー"])
            ]
        )

        #expect(lexicon.sttHotwords == ["ユーピー", "ユーピーさん", "OpenSpec"])
        #expect(lexicon.hotwordsPayload == "ユ ー ピ ー/ユ ー ピ ー さ ん/O p e n S p e c")
    }

    @Test("accepts readings as a single string")
    func acceptsSingleStringReadings() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lexiconURL = dir.appendingPathComponent("lexicon.yaml")
        try """
        version: 1
        terms:
          - text: uphy
            readings: ユーピーさん
        """.write(to: lexiconURL, atomically: true, encoding: .utf8)

        let lexicon = try TranscriptLexicon.load(from: lexiconURL)

        #expect(lexicon.terms == [
            TranscriptLexiconTerm(text: "uphy", readings: ["ユーピーさん"])
        ])
        #expect(lexicon.sttHotwords == ["ユーピーさん"])
    }

    @Test("rejects unsupported version")
    func rejectsUnsupportedVersion() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lexiconURL = dir.appendingPathComponent("lexicon.yaml")
        try """
        version: 2
        terms:
          - text: uphy
        """.write(to: lexiconURL, atomically: true, encoding: .utf8)

        var capturedError: TranscriptLexiconError?
        do {
            try TranscriptLexicon.load(from: lexiconURL)
        } catch let error as TranscriptLexiconError {
            capturedError = error
        } catch {
            #expect(false)
        }
        #expect(capturedError == .unsupportedVersion(2))
    }

    @Test("enriched editor context includes dictionary path and lexicon terms")
    func enrichedEditorContextIncludesLexiconTerms() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lexiconURL = dir.appendingPathComponent("transcript-lexicon.yaml")
        try """
        version: 1
        terms:
          - text: uphy
            readings: [ユーピー, ユーピーさん]
          - text: Chirami
            readings: チラミ
        """.write(to: lexiconURL, atomically: true, encoding: .utf8)

        let input = """
        {"file":"/tmp/note.md","selection":{"text":"","from":{"line":1,"column":0},"to":{"line":1,"column":0}},"cursor":{"line":1,"column":0},"transcript":{"text":"hello","truncated":false}}
        """
        let options = ContextRequestOptions(
            transcript: ContextTranscriptOptions(mode: .full, value: nil)
        )
        let transcriptConfig = TranscriptConfig(dictionaryFile: "./transcript-lexicon.yaml")

        let enriched = try enrichEditorContextJSON(
            input,
            options: options,
            transcriptConfig: transcriptConfig,
            configDirectory: dir
        )
        let payload = try JSONDecoder().decode(EditorContextPayload.self, from: Data(enriched.utf8))

        #expect(payload.transcript?.dictionaryFile == lexiconURL.path)
        #expect(payload.transcript?.lexiconTerms == [
            TranscriptLexiconTerm(text: "uphy", readings: ["ユーピー", "ユーピーさん"]),
            TranscriptLexiconTerm(text: "Chirami", readings: ["チラミ"])
        ])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
