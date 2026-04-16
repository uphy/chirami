import Testing
@testable import Chirami

@Suite("Transcript models")
struct TranscriptModelsTests {

    @Test("formats mic chunks with default labels")
    func formatsMicChunkWithDefaultLabels() {
        let formatter = TranscriptLineFormatter(
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let line = formatter.format(
            TranscriptChunk(
                source: .mic,
                timestamp: 1_776_340_801,
                text: "Hello world"
            )
        )
        #expect(line == "[2026-04-16 12:00:01] You: Hello world")
    }

    @Test("formats system chunks with custom labels")
    func formatsSystemChunkWithCustomLabels() {
        let formatter = TranscriptLineFormatter(
            labels: TranscriptLabelConfig(mic: "Me", system: "Room"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let line = formatter.format(
            TranscriptChunk(
                source: .system,
                timestamp: 1_776_340_809,
                text: "Audio"
            )
        )
        #expect(line == "[2026-04-16 12:00:09] Room: Audio")
    }
}
