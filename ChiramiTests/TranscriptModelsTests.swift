import Testing
@testable import Chirami

@Suite("Transcript models")
struct TranscriptModelsTests {

    @Test("formats mic chunks with default labels")
    func formatsMicChunkWithDefaultLabels() {
        let formatter = TranscriptLineFormatter()
        let line = formatter.format(TranscriptChunk(source: .mic, timestamp: 65.4, text: "Hello world"))
        #expect(line == "[01:05] You: Hello world")
    }

    @Test("formats system chunks with custom labels")
    func formatsSystemChunkWithCustomLabels() {
        let formatter = TranscriptLineFormatter(labels: TranscriptLabelConfig(mic: "Me", system: "Room"))
        let line = formatter.format(TranscriptChunk(source: .system, timestamp: 9.2, text: "Audio"))
        #expect(line == "[00:09] Room: Audio")
    }
}
