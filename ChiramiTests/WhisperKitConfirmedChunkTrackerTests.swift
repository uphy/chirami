import Foundation
import Testing
import WhisperKit
@testable import Chirami

@Suite("WhisperKit confirmed chunk tracker")
struct WhisperKitConfirmedChunkTrackerTests {
    @Test("normalizes confirmed segments into transcript chunks")
    func normalizesConfirmedSegments() {
        var tracker = WhisperKitConfirmedChunkTracker()

        let chunks = tracker.normalize(
            confirmedSegments: [
                TranscriptionSegment(id: 1, seek: 0, start: 1.25, end: 2.0, text: "  hello world  "),
                TranscriptionSegment(id: 2, seek: 0, start: 2.0, end: 3.0, text: "\nsecond line\n")
            ],
            source: .mic
        )

        #expect(chunks == [
            TranscriptChunk(source: .mic, timestamp: 1.25, text: "hello world"),
            TranscriptChunk(source: .mic, timestamp: 2.0, text: "second line")
        ])
    }

    @Test("deduplicates previously emitted segments per source")
    func deduplicatesPerSource() {
        var tracker = WhisperKitConfirmedChunkTracker()
        let segment = TranscriptionSegment(id: 7, seek: 1600, start: 5.0, end: 6.0, text: "repeat")

        let first = tracker.normalize(confirmedSegments: [segment], source: .system)
        let second = tracker.normalize(confirmedSegments: [segment], source: .system)

        #expect(first.count == 1)
        #expect(second.isEmpty)
    }

    @Test("keeps mic and system deduplication independent")
    func keepsSourcesIndependent() {
        var tracker = WhisperKitConfirmedChunkTracker()
        let segment = TranscriptionSegment(id: 3, seek: 0, start: 0.5, end: 1.5, text: "shared")

        let micChunks = tracker.normalize(confirmedSegments: [segment], source: .mic)
        let systemChunks = tracker.normalize(confirmedSegments: [segment], source: .system)

        #expect(micChunks.count == 1)
        #expect(systemChunks.count == 1)
        #expect(micChunks.first?.source == .mic)
        #expect(systemChunks.first?.source == .system)
    }

    @Test("suppresses overlap segments whose timestamps drift slightly")
    func suppressesShiftedOverlapSegments() {
        var tracker = WhisperKitConfirmedChunkTracker()

        let first = tracker.normalize(
            confirmedSegments: [
                TranscriptionSegment(id: 1, seek: 0, start: 0.0, end: 1.0, text: "hello"),
                TranscriptionSegment(id: 2, seek: 0, start: 1.0, end: 2.0, text: "world")
            ],
            source: .mic
        )

        let second = tracker.normalize(
            confirmedSegments: [
                TranscriptionSegment(id: 10, seek: 800, start: 1.1, end: 2.1, text: "world"),
                TranscriptionSegment(id: 11, seek: 800, start: 2.1, end: 3.0, text: "again")
            ],
            source: .mic
        )

        #expect(first.map(\.text) == ["hello", "world"])
        #expect(second.map(\.text) == ["again"])
    }

    @Test("emits only the novel suffix when a later segment restarts from old text")
    func emitsNovelSuffixForMergedSegment() {
        var tracker = WhisperKitConfirmedChunkTracker()

        let first = tracker.normalize(
            confirmedSegments: [
                TranscriptionSegment(id: 1, seek: 0, start: 0.0, end: 2.0, text: "共有した方がいいだろうな")
            ],
            source: .mic
        )

        let second = tracker.normalize(
            confirmedSegments: [
                TranscriptionSegment(id: 2, seek: 800, start: 1.6, end: 4.0, text: "共有した方がいいだろうなっていうところで")
            ],
            source: .mic
        )

        #expect(first.map(\.text) == ["共有した方がいいだろうな"])
        #expect(second.map(\.text) == ["っていうところで"])
    }
}
