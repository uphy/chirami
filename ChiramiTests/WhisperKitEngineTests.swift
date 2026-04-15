import AVFoundation
import Foundation
import Testing
import WhisperKit
@testable import Chirami

private final class MockWhisperTranscriber: WhisperTranscribing {
    var responses: [[TranscriptionResult]] = []
    private(set) var audioArrays: [[Float]] = []
    private(set) var languages: [String?] = []
    private(set) var detectLanguageFlags: [Bool] = []
    private(set) var usePrefillPromptFlags: [Bool] = []
    private(set) var usePrefillCacheFlags: [Bool] = []

    func transcribe(audioArray: [Float], decodeOptions: DecodingOptions?) async throws -> [TranscriptionResult] {
        audioArrays.append(audioArray)
        languages.append(decodeOptions?.language)
        detectLanguageFlags.append(decodeOptions?.detectLanguage ?? false)
        usePrefillPromptFlags.append(decodeOptions?.usePrefillPrompt ?? false)
        usePrefillCacheFlags.append(decodeOptions?.usePrefillCache ?? false)
        if responses.isEmpty {
            return []
        }
        return responses.removeFirst()
    }
}

@Suite("WhisperKit engine")
struct WhisperKitEngineTests {
    @Test("emits confirmed chunks per source and flushes tail on stop")
    func emitsConfirmedChunks() async throws {
        let transcriber = MockWhisperTranscriber()
        transcriber.responses = [
            [
                TranscriptionResultStruct(
                    text: "one two",
                    segments: [
                        TranscriptionSegment(id: 1, seek: 0, start: 0, end: 1, text: "one"),
                        TranscriptionSegment(id: 2, seek: 0, start: 1, end: 2, text: "two")
                    ],
                    language: "en",
                    timings: TranscriptionTimings()
                ).asClass()
            ],
            [
                TranscriptionResultStruct(
                    text: "system one system two",
                    segments: [
                        TranscriptionSegment(id: 10, seek: 0, start: 0, end: 1, text: "system one"),
                        TranscriptionSegment(id: 11, seek: 0, start: 1, end: 2, text: "system two")
                    ],
                    language: "en",
                    timings: TranscriptionTimings()
                ).asClass()
            ],
            [
                TranscriptionResultStruct(
                    text: "one two",
                    segments: [
                        TranscriptionSegment(id: 1, seek: 0, start: 0, end: 1, text: "one"),
                        TranscriptionSegment(id: 2, seek: 0, start: 1, end: 2, text: "two")
                    ],
                    language: "en",
                    timings: TranscriptionTimings()
                ).asClass()
            ],
            [
                TranscriptionResultStruct(
                    text: "system one system two",
                    segments: [
                        TranscriptionSegment(id: 10, seek: 0, start: 0, end: 1, text: "system one"),
                        TranscriptionSegment(id: 11, seek: 0, start: 1, end: 2, text: "system two")
                    ],
                    language: "en",
                    timings: TranscriptionTimings()
                ).asClass()
            ]
        ]

        let engine = WhisperKitEngine(
            modelFolder: URL(fileURLWithPath: "/tmp/fake-model"),
            language: "ja",
            minimumBufferSamples: 4,
            transcriberFactory: { _ in transcriber }
        )

        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        try await engine.start(audioFormat: format)

        let streamTask = Task { () -> [TranscriptChunk] in
            var chunks: [TranscriptChunk] = []
            for await chunk in engine.chunks {
                chunks.append(chunk)
            }
            return chunks
        }
        let previewTask = Task { () -> [TranscriptPreview] in
            var previews: [TranscriptPreview] = []
            for await preview in engine.previews {
                previews.append(preview)
            }
            return previews
        }

        try await engine.feed(buffer: makeBuffer(samples: [0.1, 0.2, 0.3, 0.4]), source: .mic)
        try await engine.feed(buffer: makeBuffer(samples: [0.5, 0.6, 0.7, 0.8]), source: .system)
        await Task.yield()
        await Task.yield()
        await engine.stop()

        let chunks = await streamTask.value
        let previews = await previewTask.value
        #expect(chunks == [
            TranscriptChunk(source: .mic, timestamp: 0, text: "one"),
            TranscriptChunk(source: .system, timestamp: 0, text: "system one"),
            TranscriptChunk(source: .mic, timestamp: 1, text: "two"),
            TranscriptChunk(source: .system, timestamp: 1, text: "system two")
        ])
        #expect(previews.contains(where: { $0.source == .mic && $0.text.isEmpty }))
        #expect(previews.contains(where: { $0.source == .system && $0.text.isEmpty }))
        #expect(transcriber.languages.allSatisfy { $0 == "ja" })
        #expect(transcriber.detectLanguageFlags.allSatisfy { $0 == false })
    }

    @Test("uses language detection when transcript language is auto")
    func usesLanguageDetectionForAuto() async throws {
        let transcriber = MockWhisperTranscriber()
        transcriber.responses = [[
            TranscriptionResultStruct(
                text: "hello",
                segments: [TranscriptionSegment(id: 1, seek: 0, start: 0, end: 1, text: "hello")],
                language: "en",
                timings: TranscriptionTimings()
            ).asClass()
        ]]

        let engine = WhisperKitEngine(
            modelFolder: URL(fileURLWithPath: "/tmp/fake-model"),
            language: "auto",
            minimumBufferSamples: 2,
            transcriberFactory: { _ in transcriber }
        )
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        try await engine.start(audioFormat: format)

        let streamTask = Task { () -> [TranscriptChunk] in
            var chunks: [TranscriptChunk] = []
            for await chunk in engine.chunks {
                chunks.append(chunk)
            }
            return chunks
        }

        try await engine.feed(buffer: makeBuffer(samples: [0.1, 0.2]), source: .mic)
        await Task.yield()
        await engine.stop()
        _ = await streamTask.value

        #expect(transcriber.languages == [nil])
        #expect(transcriber.detectLanguageFlags == [true])
        #expect(transcriber.usePrefillPromptFlags == [false])
        #expect(transcriber.usePrefillCacheFlags == [false])
    }

    @Test("pins auto-detected language after the first decode")
    func pinsDetectedLanguageAfterFirstDecode() async throws {
        let transcriber = MockWhisperTranscriber()
        transcriber.responses = [
            [
                TranscriptionResultStruct(
                    text: "こんにちは",
                    segments: [TranscriptionSegment(id: 1, seek: 0, start: 0, end: 1, text: "こんにちは")],
                    language: "ja",
                    timings: TranscriptionTimings()
                ).asClass()
            ],
            [
                TranscriptionResultStruct(
                    text: "世界",
                    segments: [TranscriptionSegment(id: 2, seek: 0, start: 0, end: 1, text: "世界")],
                    language: "ja",
                    timings: TranscriptionTimings()
                ).asClass()
            ]
        ]

        let engine = WhisperKitEngine(
            modelFolder: URL(fileURLWithPath: "/tmp/fake-model"),
            language: "auto",
            minimumBufferSamples: 2,
            transcriberFactory: { _ in transcriber }
        )
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        try await engine.start(audioFormat: format)

        try await engine.feed(buffer: makeBuffer(samples: [0.1, 0.2]), source: .mic)
        await Task.yield()
        await Task.yield()
        try await engine.feed(buffer: makeBuffer(samples: [0.3, 0.4]), source: .mic)
        await Task.yield()
        await Task.yield()
        await engine.stop()

        #expect(transcriber.languages == [nil, "ja"])
        #expect(transcriber.detectLanguageFlags == [true, false])
        #expect(transcriber.usePrefillPromptFlags == [false, true])
        #expect(transcriber.usePrefillCacheFlags == [false, true])
    }

    @Test("cuts utterances on silence and transcribes each utterance once")
    func cutsUtterancesOnSilence() async throws {
        let transcriber = MockWhisperTranscriber()
        transcriber.responses = [
            [
                TranscriptionResultStruct(
                    text: "first utterance",
                    segments: [TranscriptionSegment(id: 1, seek: 0, start: 0, end: 1, text: "first utterance")],
                    language: "ja",
                    timings: TranscriptionTimings()
                ).asClass()
            ],
            [
                TranscriptionResultStruct(
                    text: "second utterance",
                    segments: [TranscriptionSegment(id: 2, seek: 0, start: 0, end: 1, text: "second utterance")],
                    language: "ja",
                    timings: TranscriptionTimings()
                ).asClass()
            ]
        ]

        let engine = WhisperKitEngine(
            modelFolder: URL(fileURLWithPath: "/tmp/fake-model"),
            language: "ja",
            minimumBufferSamples: 4,
            transcriberFactory: { _ in transcriber }
        )

        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        try await engine.start(audioFormat: format)

        let streamTask = Task { () -> [TranscriptChunk] in
            var chunks: [TranscriptChunk] = []
            for await chunk in engine.chunks {
                chunks.append(chunk)
            }
            return chunks
        }

        try await engine.feed(buffer: makeBuffer(samples: [0.1, 0.2, 0.3, 0.4]), source: .mic)
        try await engine.feed(buffer: makeBuffer(samples: Array(repeating: Float(0), count: 8_000)), source: .mic)
        await Task.yield()
        await Task.yield()
        try await engine.feed(buffer: makeBuffer(samples: [0.5, 0.6, 0.7, 0.8]), source: .mic)
        try await engine.feed(buffer: makeBuffer(samples: Array(repeating: Float(0), count: 8_000)), source: .mic)
        await Task.yield()
        await Task.yield()
        await engine.stop()

        let chunks = await streamTask.value
        #expect(chunks.map(\.text) == ["first utterance", "second utterance"])
        #expect(transcriber.audioArrays.count == 2)
    }

    @Test("emits confirmed chunks during recording when provisional tail is disabled")
    func emitsChunksWhenProvisionalTailDisabled() async throws {
        let transcriber = MockWhisperTranscriber()
        transcriber.responses = [[
            TranscriptionResultStruct(
                text: "hello world",
                segments: [
                    TranscriptionSegment(id: 1, seek: 0, start: 0, end: 1, text: "hello"),
                    TranscriptionSegment(id: 2, seek: 0, start: 1, end: 2, text: "world")
                ],
                language: "en",
                timings: TranscriptionTimings()
            ).asClass()
        ]]

        let engine = WhisperKitEngine(
            modelFolder: URL(fileURLWithPath: "/tmp/fake-model"),
            language: "ja",
            minimumBufferSamples: 2,
            transcriberFactory: { _ in transcriber }
        )

        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        try await engine.start(audioFormat: format)

        let streamTask = Task { () -> [TranscriptChunk] in
            var chunks: [TranscriptChunk] = []
            for await chunk in engine.chunks {
                chunks.append(chunk)
                if chunks.count == 2 {
                    break
                }
            }
            return chunks
        }

        try await engine.feed(buffer: makeBuffer(samples: [0.1, 0.2]), source: .mic)
        await Task.yield()
        await Task.yield()

        let chunks = await streamTask.value
        await engine.stop()

        #expect(chunks.map(\.text) == ["hello", "world"])
    }

    @Test("deduplicates repeated prefixes across adjacent utterances")
    func deduplicatesRepeatedPrefixesAcrossUtterances() async throws {
        let transcriber = MockWhisperTranscriber()
        transcriber.responses = [
            [
                TranscriptionResultStruct(
                    text: "自分の中ではすごくユニークだなと思っていて",
                    segments: [
                        TranscriptionSegment(id: 1, seek: 0, start: 0, end: 1, text: "自分の中ではすごくユニークだなと思っていて")
                    ],
                    language: "ja",
                    timings: TranscriptionTimings()
                ).asClass()
            ],
            [
                TranscriptionResultStruct(
                    text: "自分の中ではすごくユニークだなと思っていて 今までコンシューマー向けの仕事をしてたんですけど",
                    segments: [
                        TranscriptionSegment(
                            id: 2,
                            seek: 0,
                            start: 0,
                            end: 2,
                            text: "自分の中ではすごくユニークだなと思っていて 今までコンシューマー向けの仕事をしてたんですけど"
                        )
                    ],
                    language: "ja",
                    timings: TranscriptionTimings()
                ).asClass()
            ]
        ]

        let engine = WhisperKitEngine(
            modelFolder: URL(fileURLWithPath: "/tmp/fake-model"),
            language: "ja",
            minimumBufferSamples: 4,
            transcriberFactory: { _ in transcriber }
        )

        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        try await engine.start(audioFormat: format)

        let streamTask = Task { () -> [TranscriptChunk] in
            var chunks: [TranscriptChunk] = []
            for await chunk in engine.chunks {
                chunks.append(chunk)
            }
            return chunks
        }

        try await engine.feed(buffer: makeBuffer(samples: [0.1, 0.2, 0.3, 0.4]), source: .mic)
        try await engine.feed(buffer: makeBuffer(samples: Array(repeating: Float(0), count: 8_000)), source: .mic)
        await Task.yield()
        await Task.yield()

        try await engine.feed(buffer: makeBuffer(samples: [0.5, 0.6, 0.7, 0.8]), source: .mic)
        try await engine.feed(buffer: makeBuffer(samples: Array(repeating: Float(0), count: 8_000)), source: .mic)
        await Task.yield()
        await Task.yield()
        await engine.stop()

        let chunks = await streamTask.value
        #expect(chunks.map(\.text) == [
            "自分の中ではすごくユニークだなと思っていて",
            "今までコンシューマー向けの仕事をしてたんですけど"
        ])
    }

    private func makeBuffer(samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            buffer.floatChannelData![0].assign(from: pointer.baseAddress!, count: samples.count)
        }
        return buffer
    }
}

private extension TranscriptionResultStruct {
    func asClass() -> TranscriptionResult {
        TranscriptionResult(
            text: text,
            segments: segments,
            language: language,
            timings: timings,
            seekTime: seekTime
        )
    }
}
