import AVFoundation
import Foundation
import OSLog
import WhisperKit

protocol WhisperTranscribing: AnyObject {
    func transcribe(audioArray: [Float], decodeOptions: DecodingOptions?) async throws -> [TranscriptionResult]
}

final class WhisperKitTranscriber: WhisperTranscribing {
    private let whisperKit: WhisperKit

    init(modelFolder: URL) async throws {
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            verbose: false,
            logLevel: .none,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
    }

    func transcribe(audioArray: [Float], decodeOptions: DecodingOptions?) async throws -> [TranscriptionResult] {
        try await whisperKit.transcribe(audioArray: audioArray, decodeOptions: decodeOptions)
    }
}

actor WhisperKitEngine: TranscriptionEngine {
    typealias TranscriberFactory = (_ modelFolder: URL) async throws -> any WhisperTranscribing

    private struct QueuedUtterance {
        var samples: [Float]
        var startSampleOffset: Int
    }

    private struct SourceState {
        var totalSampleCount = 0
        var prerollSamples: [Float] = []
        var utteranceSamples: [Float] = []
        var utteranceStartSampleOffset: Int?
        var utteranceSpeechSampleCount = 0
        var utteranceTrailingSilenceSampleCount = 0
        var queuedUtterances: [QueuedUtterance] = []
        var isProcessing = false
        var resolvedLanguage: String?
        var emittedTextTail = ""
    }

    private static let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "Transcript")
    private static let autoLanguageMinimumUtteranceSamples = WhisperKit.sampleRate * 2
    private static let explicitLanguageMinimumUtteranceSamples = Int(Double(WhisperKit.sampleRate) * 0.75)
    private static let speechThreshold: Float = 0.0015
    private static let prerollSampleCount = Int(Double(WhisperKit.sampleRate) * 0.25)
    private static let trailingSilenceSampleCount = Int(Double(WhisperKit.sampleRate) * 0.45)
    private static let maxUtteranceSampleCount = WhisperKit.sampleRate * 20
    private static let emittedTextTailLength = 256

    private let modelFolder: URL
    private let language: String?
    private let transcriberFactory: TranscriberFactory
    private let minimumUtteranceSamples: Int
    private let chunkStream: AsyncStream<TranscriptChunk>
    private let previewStream: AsyncStream<TranscriptPreview>

    private var transcriber: (any WhisperTranscribing)?
    private var sourceStates: [TranscriptSource: SourceState] = [:]
    private var continuation: AsyncStream<TranscriptChunk>.Continuation?
    private var previewContinuation: AsyncStream<TranscriptPreview>.Continuation?
    private var started = false
    private var stopped = false

    init(
        modelFolder: URL,
        language: String?,
        minimumBufferSamples: Int? = nil,
        transcriberFactory: @escaping TranscriberFactory = { modelFolder in
            try await WhisperKitTranscriber(modelFolder: modelFolder)
        }
    ) {
        self.modelFolder = modelFolder
        self.language = Self.normalizedLanguage(language)
        self.minimumUtteranceSamples = minimumBufferSamples ?? {
            if Self.normalizedLanguage(language) == nil {
                Self.logger.info("transcript auto language enabled; using utterance segmentation with extended minimum duration")
                return Self.autoLanguageMinimumUtteranceSamples
            }
            return Self.explicitLanguageMinimumUtteranceSamples
        }()
        self.transcriberFactory = transcriberFactory
        var continuation: AsyncStream<TranscriptChunk>.Continuation?
        self.chunkStream = AsyncStream { streamContinuation in
            continuation = streamContinuation
        }
        self.continuation = continuation
        var previewContinuation: AsyncStream<TranscriptPreview>.Continuation?
        self.previewStream = AsyncStream { streamContinuation in
            previewContinuation = streamContinuation
        }
        self.previewContinuation = previewContinuation
    }

    nonisolated var chunks: AsyncStream<TranscriptChunk> {
        chunkStream
    }

    nonisolated var previews: AsyncStream<TranscriptPreview> {
        previewStream
    }

    func start(audioFormat: AVAudioFormat) async throws {
        guard !started else {
            return
        }
        guard audioFormat.commonFormat == .pcmFormatFloat32,
              !audioFormat.isInterleaved,
              audioFormat.channelCount == 1
        else {
            throw WhisperKitEngineError.unsupportedAudioFormat
        }

        transcriber = try await transcriberFactory(modelFolder)
        sourceStates[.mic] = SourceState()
        sourceStates[.system] = SourceState()
        started = true
        stopped = false
    }

    func feed(buffer: AVAudioPCMBuffer, source: TranscriptSource) async throws {
        guard started, !stopped else {
            return
        }

        let samples = extractSamples(from: buffer)
        guard !samples.isEmpty else {
            return
        }

        var state = sourceStates[source] ?? SourceState()
        let frameLevel = samples.rmsLevel()
        let isSpeech = frameLevel >= Self.speechThreshold
        let currentSampleOffset = state.totalSampleCount
        state.totalSampleCount += samples.count

        if let utteranceStartSampleOffset = state.utteranceStartSampleOffset {
            state.utteranceSamples.append(contentsOf: samples)
            if isSpeech {
                state.utteranceSpeechSampleCount += samples.count
                state.utteranceTrailingSilenceSampleCount = 0
            } else {
                state.utteranceTrailingSilenceSampleCount += samples.count
            }

            let reachedSilenceBoundary =
                state.utteranceSpeechSampleCount >= minimumUtteranceSamples &&
                state.utteranceTrailingSilenceSampleCount >= Self.trailingSilenceSampleCount
            let reachedMaxLength = state.utteranceSamples.count >= Self.maxUtteranceSampleCount

            if reachedSilenceBoundary || reachedMaxLength {
                enqueueUtterance(
                    &state,
                    startSampleOffset: utteranceStartSampleOffset,
                    dropTrailingSilence: reachedSilenceBoundary && !reachedMaxLength
                )
            }
        } else if isSpeech {
            state.utteranceStartSampleOffset = max(0, currentSampleOffset - state.prerollSamples.count)
            state.utteranceSamples = state.prerollSamples + samples
            state.utteranceSpeechSampleCount = samples.count
            state.utteranceTrailingSilenceSampleCount = 0
            state.prerollSamples.removeAll(keepingCapacity: true)
        } else {
            state.prerollSamples.append(contentsOf: samples)
            if state.prerollSamples.count > Self.prerollSampleCount {
                state.prerollSamples.removeFirst(state.prerollSamples.count - Self.prerollSampleCount)
            }
        }

        let shouldStartProcessing = !state.isProcessing && !state.queuedUtterances.isEmpty
        sourceStates[source] = state

        if shouldStartProcessing {
            Task { await self.processNextQueuedUtterance(source: source) }
        }
    }

    func stop() async {
        guard started, !stopped else {
            return
        }
        stopped = true

        await flushPendingUtterance(for: .mic)
        await flushPendingUtterance(for: .system)
        await processNextQueuedUtterance(source: .mic)
        await processNextQueuedUtterance(source: .system)

        continuation?.finish()
        continuation = nil
        previewContinuation?.finish()
        previewContinuation = nil
    }

    private func flushPendingUtterance(for source: TranscriptSource) async {
        var state = sourceStates[source] ?? SourceState()
        guard let utteranceStartSampleOffset = state.utteranceStartSampleOffset else {
            sourceStates[source] = state
            return
        }

        if state.utteranceSpeechSampleCount > 0 {
            enqueueUtterance(
                &state,
                startSampleOffset: utteranceStartSampleOffset,
                dropTrailingSilence: true
            )
        } else {
            clearCurrentUtterance(&state)
        }
        sourceStates[source] = state
    }

    private func processNextQueuedUtterance(source: TranscriptSource) async {
        guard let transcriber else {
            return
        }

        var state = sourceStates[source] ?? SourceState()
        guard !state.isProcessing, !state.queuedUtterances.isEmpty else {
            sourceStates[source] = state
            return
        }

        state.isProcessing = true
        let utterance = state.queuedUtterances.removeFirst()
        sourceStates[source] = state

        let decodeOptions = makeDecodeOptions(for: state)

        do {
            let results = try await transcriber.transcribe(audioArray: utterance.samples, decodeOptions: decodeOptions)
            if language == nil,
               state.resolvedLanguage == nil,
               let detectedLanguage = normalizedDetectedLanguage(from: results) {
                var updatedState = sourceStates[source] ?? SourceState()
                updatedState.resolvedLanguage = detectedLanguage
                sourceStates[source] = updatedState
                Self.logger.info(
                    "transcript pinned detected language source=\(source.rawValue, privacy: .public) language=\(detectedLanguage, privacy: .public)"
                )
            }
            let segments = results.flatMap(\.segments)
            let baseTimestamp = TimeInterval(utterance.startSampleOffset) / Double(WhisperKit.sampleRate)
            var latestState = sourceStates[source] ?? state
            for segment in segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    continue
                }
                let emittedText = deduplicate(text: text, against: latestState.emittedTextTail)
                guard !emittedText.isEmpty else {
                    continue
                }
                continuation?.yield(
                    TranscriptChunk(
                        source: source,
                        timestamp: baseTimestamp + TimeInterval(segment.start),
                        text: emittedText
                    )
                )
                latestState.emittedTextTail = updateTail(latestState.emittedTextTail, appending: emittedText)
                sourceStates[source] = latestState
            }
            previewContinuation?.yield(TranscriptPreview(source: source, timestamp: baseTimestamp, text: ""))
        } catch {
            continuation?.finish()
            previewContinuation?.finish()
        }

        var latest = sourceStates[source] ?? SourceState()
        latest.isProcessing = false
        let hasMoreQueuedUtterances = !latest.queuedUtterances.isEmpty
        sourceStates[source] = latest

        if hasMoreQueuedUtterances {
            await processNextQueuedUtterance(source: source)
        }
    }

    private func enqueueUtterance(
        _ state: inout SourceState,
        startSampleOffset: Int,
        dropTrailingSilence: Bool
    ) {
        var utteranceSamples = state.utteranceSamples
        if dropTrailingSilence, state.utteranceTrailingSilenceSampleCount > 0 {
            let trimmedCount = max(0, utteranceSamples.count - state.utteranceTrailingSilenceSampleCount)
            utteranceSamples = Array(utteranceSamples.prefix(trimmedCount))
        }

        if utteranceSamples.count >= minimumUtteranceSamples {
            state.queuedUtterances.append(
                QueuedUtterance(
                    samples: utteranceSamples,
                    startSampleOffset: startSampleOffset
                )
            )
        }

        clearCurrentUtterance(&state)
    }

    private func clearCurrentUtterance(_ state: inout SourceState) {
        state.prerollSamples.removeAll(keepingCapacity: true)
        state.utteranceSamples.removeAll(keepingCapacity: true)
        state.utteranceStartSampleOffset = nil
        state.utteranceSpeechSampleCount = 0
        state.utteranceTrailingSilenceSampleCount = 0
    }

    private func deduplicate(text: String, against tail: String) -> String {
        guard !tail.isEmpty else {
            return text
        }

        let textCharacters = Array(text)
        let tailCharacters = Array(tail)
        let maxOverlap = min(textCharacters.count, tailCharacters.count)

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            let tailSuffix = tailCharacters.suffix(overlap)
            let textPrefix = textCharacters.prefix(overlap)
            if Array(tailSuffix) == Array(textPrefix) {
                return String(textCharacters.dropFirst(overlap)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return text
    }

    private func updateTail(_ existingTail: String, appending text: String) -> String {
        let combined = existingTail.isEmpty ? text : "\(existingTail)\n\(text)"
        let characters = Array(combined)
        guard characters.count > Self.emittedTextTailLength else {
            return combined
        }
        return String(characters.suffix(Self.emittedTextTailLength))
    }

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return []
        }

        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)
        return Array(samples)
    }

    private func makeDecodeOptions(for state: SourceState) -> DecodingOptions {
        let effectiveLanguage = state.resolvedLanguage ?? language
        return DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: effectiveLanguage,
            temperature: 0,
            usePrefillPrompt: effectiveLanguage != nil,
            usePrefillCache: effectiveLanguage != nil,
            detectLanguage: effectiveLanguage == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: false,
            windowClipTime: 0.2,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.45,
            chunkingStrategy: nil
        )
    }

    private static func normalizedLanguage(_ language: String?) -> String? {
        guard let language else {
            return nil
        }
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "auto" else {
            return nil
        }
        return trimmed
    }

    private func normalizedDetectedLanguage(from results: [TranscriptionResult]) -> String? {
        guard let language = results.lazy
            .map(\.language)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return nil
        }
        return Self.normalizedLanguage(language)
    }
}

enum WhisperKitEngineError: LocalizedError, Equatable {
    case unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedAudioFormat:
            return "WhisperKitEngine requires 16kHz mono float32 PCM buffers."
        }
    }
}

private extension Array where Element == Float {
    func rmsLevel() -> Float {
        guard !isEmpty else {
            return 0
        }

        var energy: Float = 0
        for sample in self {
            energy += sample * sample
        }
        return sqrt(energy / Float(count))
    }
}
