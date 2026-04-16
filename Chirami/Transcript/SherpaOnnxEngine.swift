import AVFoundation
import Foundation
import OSLog

protocol SherpaOnnxTranscribing: AnyObject {
    func transcribe(samples: [Float]) throws -> SherpaOnnxOfflineRecognitionResult
}

final class SherpaOnnxSenseVoiceTranscriber: SherpaOnnxTranscribing {
    private let recognizer: SherpaOnnxOfflineRecognizerWrapper

    init(modelFolder: URL, language: String?) throws {
        let modelPath = modelFolder.appendingPathComponent("model.int8.onnx").path
        let tokensPath = modelFolder.appendingPathComponent("tokens.txt").path
        let senseVoiceConfig = sherpaOnnxOfflineSenseVoiceModelConfig(
            model: modelPath,
            language: language ?? "",
            useInverseTextNormalization: true
        )
        var modelConfig = sherpaOnnxOfflineModelConfig(tokens: tokensPath)
        modelConfig.sense_voice = senseVoiceConfig
        let featureConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var recognizerConfig = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featureConfig,
            modelConfig: modelConfig
        )
        recognizer = try SherpaOnnxOfflineRecognizerWrapper(config: &recognizerConfig)
    }

    func transcribe(samples: [Float]) throws -> SherpaOnnxOfflineRecognitionResult {
        try recognizer.decode(samples: samples, sampleRate: 16_000)
    }
}

final class SherpaOnnxNemoCTCTranscriber: SherpaOnnxTranscribing {
    private let recognizer: SherpaOnnxOfflineRecognizerWrapper

    init(modelFolder: URL) throws {
        let modelPath = modelFolder.appendingPathComponent("model.int8.onnx").path
        let tokensPath = modelFolder.appendingPathComponent("tokens.txt").path
        let nemoConfig = sherpaOnnxOfflineNemoEncDecCtcModelConfig(model: modelPath)
        var modelConfig = sherpaOnnxOfflineModelConfig(tokens: tokensPath)
        modelConfig.nemo_ctc = nemoConfig
        let featureConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var recognizerConfig = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featureConfig,
            modelConfig: modelConfig
        )
        recognizer = try SherpaOnnxOfflineRecognizerWrapper(config: &recognizerConfig)
    }

    func transcribe(samples: [Float]) throws -> SherpaOnnxOfflineRecognitionResult {
        try recognizer.decode(samples: samples, sampleRate: 16_000)
    }
}

actor SherpaOnnxTranscriberWorker {
    private let transcriber: any SherpaOnnxTranscribing

    init(transcriber: any SherpaOnnxTranscribing) {
        self.transcriber = transcriber
    }

    func transcribe(samples: [Float]) throws -> SherpaOnnxOfflineRecognitionResult {
        try transcriber.transcribe(samples: samples)
    }
}

actor SherpaOnnxEngine: TranscriptionEngine {
    typealias TranscriberFactory = (_ modelFolder: URL, _ language: String?) throws -> any SherpaOnnxTranscribing

    private struct QueuedUtterance {
        var samples: [Float]
        var startSampleOffset: Int
    }

    private struct SourceState {
        var totalSampleCount = 0
        var smoothedLevel: Float = 0
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
    private static let sampleRate = 16_000
    private static let autoLanguageMinimumUtteranceSamples = sampleRate * 2
    private static let explicitLanguageMinimumUtteranceSamples = Int(Double(sampleRate) * 1.2)
    private static let speechStartThreshold: Float = 0.0012
    private static let speechContinueThreshold: Float = 0.0006
    private static let levelSmoothingFactor: Float = 0.85
    private static let prerollSampleCount = Int(Double(sampleRate) * 0.35)
    private static let trailingSilenceSampleCount = Int(Double(sampleRate) * 0.8)
    private static let maxUtteranceSampleCount = sampleRate * 20
    private static let emittedTextTailLength = 256

    private let modelFolder: URL
    private let language: String?
    private let transcriberFactory: TranscriberFactory
    private let minimumUtteranceSamples: Int
    private let chunkStream: AsyncStream<TranscriptChunk>
    private let previewStream: AsyncStream<TranscriptPreview>

    private var transcriberWorker: SherpaOnnxTranscriberWorker?
    private var sourceStates: [TranscriptSource: SourceState] = [:]
    private var continuation: AsyncStream<TranscriptChunk>.Continuation?
    private var previewContinuation: AsyncStream<TranscriptPreview>.Continuation?
    private var started = false
    private var stopped = false
    private var stopMode: TranscriptionEngineStopMode?
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        modelFolder: URL,
        modelKind: SherpaOnnxModelKind = .senseVoice,
        language: String?,
        minimumBufferSamples: Int? = nil,
        transcriberFactory: TranscriberFactory? = nil
    ) {
        let normalizedLanguage = modelKind == .senseVoice ? Self.normalizedLanguage(language) : nil
        self.modelFolder = modelFolder
        self.language = normalizedLanguage
        self.minimumUtteranceSamples = minimumBufferSamples ?? {
            if modelKind == .senseVoice, normalizedLanguage == nil {
                Self.logger.info("transcript sherpa auto language enabled; using extended minimum utterance duration")
                return Self.autoLanguageMinimumUtteranceSamples
            }
            return Self.explicitLanguageMinimumUtteranceSamples
        }()
        self.transcriberFactory = transcriberFactory ?? { modelFolder, language in
            switch modelKind {
            case .senseVoice:
                return try SherpaOnnxSenseVoiceTranscriber(modelFolder: modelFolder, language: language)
            case .nemoCTC:
                return try SherpaOnnxNemoCTCTranscriber(modelFolder: modelFolder)
            }
        }
        var chunkContinuation: AsyncStream<TranscriptChunk>.Continuation?
        self.chunkStream = AsyncStream { continuation in
            chunkContinuation = continuation
        }
        continuation = chunkContinuation
        var previewContinuation: AsyncStream<TranscriptPreview>.Continuation?
        self.previewStream = AsyncStream { continuation in
            previewContinuation = continuation
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
            throw SherpaOnnxEngineError.unsupportedAudioFormat
        }

        let transcriber = try transcriberFactory(modelFolder, language)
        transcriberWorker = SherpaOnnxTranscriberWorker(transcriber: transcriber)
        sourceStates[.mic] = SourceState()
        sourceStates[.system] = SourceState()
        started = true
        stopped = false
        stopMode = nil
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
        let frameLevel = samples.chiramiRmsLevel()
        let smoothedLevel = max(
            frameLevel,
            (state.smoothedLevel * Self.levelSmoothingFactor) +
                (frameLevel * (1 - Self.levelSmoothingFactor))
        )
        state.smoothedLevel = smoothedLevel
        let isSpeech: Bool
        if state.utteranceStartSampleOffset != nil {
            isSpeech = smoothedLevel >= Self.speechContinueThreshold
        } else {
            isSpeech = smoothedLevel >= Self.speechStartThreshold
        }
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

        sourceStates[source] = state

        scheduleQueuedUtteranceIfNeeded(for: source)
    }

    func stop(mode: TranscriptionEngineStopMode) async {
        guard started, !stopped else {
            return
        }
        stopped = true
        stopMode = mode

        switch mode {
        case .flushFinalChunks:
            await flushPendingUtterance(for: .mic)
            await flushPendingUtterance(for: .system)
            scheduleQueuedUtteranceIfNeeded(for: .mic)
            scheduleQueuedUtteranceIfNeeded(for: .system)
            await waitUntilDrained()
        case .discardPendingWork:
            discardPendingWork()
        }

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

    private func scheduleQueuedUtteranceIfNeeded(for source: TranscriptSource) {
        guard let transcriberWorker else {
            return
        }

        var state = sourceStates[source] ?? SourceState()
        guard !state.isProcessing, !state.queuedUtterances.isEmpty else {
            sourceStates[source] = state
            notifyDrainedIfNeeded()
            return
        }

        state.isProcessing = true
        let utterance = state.queuedUtterances.removeFirst()
        sourceStates[source] = state

        Task { [weak self] in
            let result: Result<SherpaOnnxOfflineRecognitionResult, Error>
            do {
                result = .success(try await transcriberWorker.transcribe(samples: utterance.samples))
            } catch {
                result = .failure(error)
            }
            await self?.finishQueuedUtterance(source: source, utterance: utterance, result: result)
        }
    }

    private func finishQueuedUtterance(
        source: TranscriptSource,
        utterance: QueuedUtterance,
        result: Result<SherpaOnnxOfflineRecognitionResult, Error>
    ) async {
        defer {
            var latest = sourceStates[source] ?? SourceState()
            latest.isProcessing = false
            sourceStates[source] = latest
            if stopMode != .discardPendingWork {
                scheduleQueuedUtteranceIfNeeded(for: source)
            } else {
                notifyDrainedIfNeeded()
            }
        }

        if stopMode == .discardPendingWork {
            return
        }

        switch result {
        case .success(let recognitionResult):
            var state = sourceStates[source] ?? SourceState()
            if language == nil,
               state.resolvedLanguage == nil {
                let detectedLanguage = Self.normalizedLanguage(recognitionResult.language)
                if let detectedLanguage {
                    state.resolvedLanguage = detectedLanguage
                    sourceStates[source] = state
                    Self.logger.info(
                        "transcript sherpa pinned detected language source=\(source.rawValue, privacy: .public) language=\(detectedLanguage, privacy: .public)"
                    )
                }
            }

            let baseTimestamp = TimeInterval(utterance.startSampleOffset) / Double(Self.sampleRate)
            var latestState = sourceStates[source] ?? state
            for segment in recognitionResult.segments {
                let emittedText = deduplicate(text: segment.text, against: latestState.emittedTextTail)
                guard !emittedText.isEmpty else {
                    continue
                }
                continuation?.yield(
                    TranscriptChunk(
                        source: source,
                        timestamp: baseTimestamp + segment.start,
                        text: emittedText
                    )
                )
                latestState.emittedTextTail = updateTail(latestState.emittedTextTail, appending: emittedText)
                sourceStates[source] = latestState
            }
            previewContinuation?.yield(TranscriptPreview(source: source, timestamp: baseTimestamp, text: ""))
        case .failure:
            continuation?.finish()
            continuation = nil
            previewContinuation?.finish()
            previewContinuation = nil
            stopped = true
            stopMode = .discardPendingWork
            discardPendingWork()
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

    private func discardPendingWork() {
        for source in [TranscriptSource.mic, .system] {
            var state = sourceStates[source] ?? SourceState()
            state.queuedUtterances.removeAll(keepingCapacity: false)
            clearCurrentUtterance(&state)
            sourceStates[source] = state
        }
        notifyDrainedIfNeeded()
    }

    private func waitUntilDrained() async {
        if isDrained {
            return
        }
        await withCheckedContinuation { continuation in
            drainWaiters.append(continuation)
        }
    }

    private var isDrained: Bool {
        sourceStates.values.allSatisfy { !$0.isProcessing && $0.queuedUtterances.isEmpty && $0.utteranceStartSampleOffset == nil }
    }

    private func notifyDrainedIfNeeded() {
        guard isDrained else {
            return
        }
        let waiters = drainWaiters
        drainWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func deduplicate(text: String, against tail: String) -> String {
        guard !tail.isEmpty else {
            return text
        }

        let textCharacters = Array(text)
        let tailCharacters = Array(tail)
        let maxOverlap = min(textCharacters.count, tailCharacters.count)

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            if Array(tailCharacters.suffix(overlap)) == Array(textCharacters.prefix(overlap)) {
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
}

enum SherpaOnnxEngineError: LocalizedError, Equatable {
    case unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedAudioFormat:
            return "SherpaOnnxEngine requires 16kHz mono float32 PCM buffers."
        }
    }
}

private extension Array where Element == Float {
    func chiramiRmsLevel() -> Float {
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
