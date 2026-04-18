import Foundation
import AVFoundation
import OSLog

protocol MicrophoneCapturing: AnyObject {
    func start(bufferHandler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws
    func pause()
    func resume() throws
    func stop()
}

protocol SystemAudioCapturing: AnyObject {
    func start(processes: [AudioProcessDescriptor], bufferHandler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws
    func pause()
    func resume() throws
    func stop()
}

struct TranscriptSessionContext: Sendable {
    var range: TranscriptBlockRange
    var modelLabel: String
    var micEnabled: Bool
    var micDeviceLabel: String
    var systemDeviceLabel: String
    var labels: TranscriptLabelConfig
}

private struct TranscriptTimelineAnchor: Sendable {
    var audioOffset: TimeInterval
    var wallClock: Date
}

@MainActor
final class TranscriptSessionCallbacks {
    var sendChunk: ((TranscriptChunkMessage) -> Void)?
    var sendPreview: ((TranscriptPreviewMessage) -> Void)?
    var sendState: ((TranscriptStateMessage) -> Void)?
    var sendLevel: ((TranscriptLevelUpdateMessage) -> Void)?
    var sendModelDownloadProgress: ((TranscriptModelDownloadProgressMessage) -> Void)?
    var sendError: ((TranscriptErrorMessage) -> Void)?

    func chunk(_ message: TranscriptChunkMessage) {
        sendChunk?(message)
    }

    func preview(_ message: TranscriptPreviewMessage) {
        sendPreview?(message)
    }

    func state(_ message: TranscriptStateMessage) {
        sendState?(message)
    }

    func level(_ message: TranscriptLevelUpdateMessage) {
        sendLevel?(message)
    }

    func modelDownloadProgress(_ message: TranscriptModelDownloadProgressMessage) {
        sendModelDownloadProgress?(message)
    }

    func error(_ message: TranscriptErrorMessage) {
        sendError?(message)
    }
}

typealias TranscriptTranscriptionEngineFactory = @Sendable (
    _ progress: @escaping SherpaOnnxModelDownloadProgressHandler
) async throws -> TranscriptionEngine?

actor TranscriptSession {
    private static let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "TranscriptSession")

    private let context: TranscriptSessionContext
    private let callbacks: TranscriptSessionCallbacks
    private let microphoneCapture: MicrophoneCapturing
    private let systemAudioCapture: SystemAudioCapturing?
    private let transcriptionEngineFactory: TranscriptTranscriptionEngineFactory?
    private let systemProcesses: [AudioProcessDescriptor]
    private let requestMicrophoneAccess: @Sendable () async throws -> Void
    private let dateProvider: @Sendable () -> Date
    private let lineFormatter: TranscriptLineFormatter
    private let transcriptionStopTimeoutNanoseconds: UInt64

    private var status: TranscriptStatus = .idle
    private var chunkForwardingTask: Task<Void, Never>?
    private var previewForwardingTask: Task<Void, Never>?
    private var transcriptionEngine: TranscriptionEngine?
    private var transcriptionPreparationTask: Task<TranscriptionEngine?, Error>?
    private var isPreparingTranscriptionEngine = false
    private var suppressOutput = false
    private var recordingTimeline: [TranscriptTimelineAnchor] = []
    private var recordedAudioOffset: TimeInterval = 0
    private var activeRecordingWallClock: Date?
    private static let transcriptAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    init(
        context: TranscriptSessionContext,
        callbacks: TranscriptSessionCallbacks,
        microphoneCapture: MicrophoneCapturing = MicrophoneCapture(),
        systemAudioCapture: SystemAudioCapturing? = SystemAudioCapture(),
        transcriptionEngine: TranscriptionEngine? = nil,
        transcriptionEngineFactory: TranscriptTranscriptionEngineFactory? = nil,
        systemProcesses: [AudioProcessDescriptor] = [],
        requestMicrophoneAccess: @escaping @Sendable () async throws -> Void = {
            try await MicrophoneCapture.requestAccessIfNeeded()
        },
        dateProvider: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current,
        transcriptionStopTimeoutNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.context = context
        self.callbacks = callbacks
        self.microphoneCapture = microphoneCapture
        self.systemAudioCapture = systemAudioCapture
        self.transcriptionEngine = transcriptionEngine
        self.transcriptionEngineFactory = transcriptionEngineFactory
        self.systemProcesses = systemProcesses
        self.requestMicrophoneAccess = requestMicrophoneAccess
        self.dateProvider = dateProvider
        self.lineFormatter = TranscriptLineFormatter(labels: context.labels, timeZone: timeZone)
        self.transcriptionStopTimeoutNanoseconds = transcriptionStopTimeoutNanoseconds
    }

    func start() async {
        guard status == .idle || status == .completed || status == .error else {
            return
        }
        suppressOutput = false
        recordingTimeline = []
        recordedAudioOffset = 0
        activeRecordingWallClock = nil

        if context.micEnabled {
            do {
                try await requestMicrophoneAccess()
            } catch {
                await transitionToError(error.localizedDescription)
                return
            }
        }

        do {
            try await prepareTranscriptionEngineIfNeeded()
            if let transcriptionEngine {
                try await transcriptionEngine.start(audioFormat: Self.transcriptAudioFormat)
                startForwardingChunks()
            }
        } catch {
            if isPreparationCancellation(error) {
                return
            }
            await transitionToError(error.localizedDescription)
            return
        }

        guard !isPreparingTranscriptionEngine else {
            return
        }

        await clearModelDownloadProgress()

        if context.micEnabled {
            do {
                try microphoneCapture.start { [weak self] buffer in
                    Task {
                        await self?.handleBuffer(source: .mic, buffer: buffer)
                    }
                }
            } catch {
                await transitionToError(error.localizedDescription)
                return
            }
        }

        if let systemAudioCapture, !systemProcesses.isEmpty {
            do {
                try systemAudioCapture.start(processes: systemProcesses) { [weak self] buffer in
                    Task {
                        await self?.handleBuffer(source: .system, buffer: buffer)
                    }
                }
            } catch {
                await sendError(error.localizedDescription)
            }
        }

        beginRecordingTimelineSegment(at: dateProvider())
        status = .recording
        await sendState(status: .recording)
        await sendLevel(source: .mic, level: 0)
        await sendLevel(source: .system, level: 0)
    }

    func pause() async {
        guard status == .recording else {
            return
        }

        if context.micEnabled {
            microphoneCapture.pause()
        }
        systemAudioCapture?.pause()
        closeRecordingTimelineSegment(at: dateProvider())
        status = .paused
        await sendState(status: .paused)
        await sendLevel(source: .mic, level: 0)
        await sendLevel(source: .system, level: 0)
    }

    func resume() async {
        guard status == .paused else {
            return
        }

        do {
            if context.micEnabled {
                try microphoneCapture.resume()
            }
            try systemAudioCapture?.resume()
        } catch {
            await transitionToError(error.localizedDescription)
            return
        }

        beginRecordingTimelineSegment(at: dateProvider())
        status = .recording
        await sendState(status: .recording)
    }

    func stop() async {
        if isPreparingTranscriptionEngine {
            transcriptionPreparationTask?.cancel()
            transcriptionPreparationTask = nil
            isPreparingTranscriptionEngine = false
            status = .idle
            await clearModelDownloadProgress()
            await sendState(status: .idle)
            await sendLevel(source: .mic, level: 0)
            await sendLevel(source: .system, level: 0)
            return
        }

        guard status == .recording || status == .paused else {
            return
        }

        status = .processing
        await sendState(status: .processing)
        await sendLevel(source: .mic, level: 0)
        await sendLevel(source: .system, level: 0)

        microphoneCapture.stop()
        systemAudioCapture?.stop()
        closeRecordingTimelineSegment(at: dateProvider())
        await stopTranscriptionEngine(flushFinalChunks: true)

        status = .completed
        await clearModelDownloadProgress()
        await sendState(status: .completed)
    }

    func clear() async {
        suppressOutput = true
        status = .idle
        await clearModelDownloadProgress()
        await sendState(status: .idle)
        await sendLevel(source: .mic, level: 0)
        await sendLevel(source: .system, level: 0)

        transcriptionPreparationTask?.cancel()
        transcriptionPreparationTask = nil
        isPreparingTranscriptionEngine = false
        microphoneCapture.stop()
        systemAudioCapture?.stop()
        closeRecordingTimelineSegment(at: dateProvider())
        await stopTranscriptionEngine(flushFinalChunks: false)
    }

    private func handleBuffer(source: TranscriptSource, buffer: AVAudioPCMBuffer) async {
        guard status == .recording else {
            return
        }

        let level = AudioLevelMeter.normalizedLevel(for: buffer)
        await sendLevel(source: source, level: level)

        guard let transcriptionEngine else {
            return
        }

        guard bufferMatchesTranscriptFormat(buffer) else {
            return
        }

        do {
            try await transcriptionEngine.feed(buffer: buffer, source: source)
        } catch {
            await transitionToError(error.localizedDescription)
        }
    }

    private func bufferMatchesTranscriptFormat(_ buffer: AVAudioPCMBuffer) -> Bool {
        let format = buffer.format
        return format.commonFormat == .pcmFormatFloat32 &&
            !format.isInterleaved &&
            format.channelCount == 1 &&
            abs(format.sampleRate - Self.transcriptAudioFormat.sampleRate) < 0.5
    }

    private func transitionToError(_ message: String) async {
        suppressOutput = true
        transcriptionPreparationTask?.cancel()
        transcriptionPreparationTask = nil
        isPreparingTranscriptionEngine = false
        microphoneCapture.stop()
        systemAudioCapture?.stop()
        closeRecordingTimelineSegment(at: dateProvider())
        await stopTranscriptionEngine(flushFinalChunks: false)
        status = .error
        await clearModelDownloadProgress()
        await sendState(status: .error)
        await sendError(message)
        await sendLevel(source: .mic, level: 0)
        await sendLevel(source: .system, level: 0)
    }

    private func prepareTranscriptionEngineIfNeeded() async throws {
        guard transcriptionEngine == nil, let transcriptionEngineFactory else {
            return
        }

        isPreparingTranscriptionEngine = true
        status = .processing
        await sendState(status: .processing)
        await sendLevel(source: .mic, level: 0)
        await sendLevel(source: .system, level: 0)

        let task = Task<TranscriptionEngine?, Error> {
            try await transcriptionEngineFactory { receivedBytes, totalBytes, fractionCompleted, stage in
                Task {
                    await self.sendModelDownloadProgress(
                        fractionCompleted: min(max(fractionCompleted, 0), 1),
                        receivedBytes: max(0, Int(receivedBytes)),
                        totalBytes: Int(totalBytes ?? -1),
                        stage: stage
                    )
                }
            }
        }
        transcriptionPreparationTask = task
        defer {
            transcriptionPreparationTask = nil
            isPreparingTranscriptionEngine = false
        }

        do {
            transcriptionEngine = try await task.value
        } catch {
            if isPreparationCancellation(error) {
                throw CancellationError()
            }
            throw error
        }
    }

    private func isPreparationCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if case .cancelledDownloadingModel = error as? SherpaOnnxModelStoreError {
            return true
        }
        return false
    }

    private func startForwardingChunks() {
        guard chunkForwardingTask == nil else {
            return
        }

        chunkForwardingTask = Task { [weak self] in
            await self?.forwardChunks()
        }
        previewForwardingTask = Task { [weak self] in
            await self?.forwardPreviews()
        }
    }

    private func forwardChunks() async {
        guard let transcriptionEngine else {
            return
        }

        for await chunk in transcriptionEngine.chunks {
            await sendChunk(chunk)
        }
    }

    private func forwardPreviews() async {
        guard let transcriptionEngine else {
            return
        }

        for await preview in transcriptionEngine.previews {
            await sendPreview(preview)
        }
    }

    private func stopTranscriptionEngine(flushFinalChunks: Bool) async {
        let chunkTask = chunkForwardingTask
        let previewTask = previewForwardingTask
        let engine = transcriptionEngine

        chunkForwardingTask = nil
        previewForwardingTask = nil
        transcriptionEngine = nil

        guard let engine else {
            chunkTask?.cancel()
            previewTask?.cancel()
            return
        }

        if flushFinalChunks {
            let didFinish = await completeWithin(timeoutNanoseconds: transcriptionStopTimeoutNanoseconds) {
                await engine.stop(mode: .flushFinalChunks)
                _ = await chunkTask?.result
                _ = await previewTask?.result
            }
            if !didFinish {
                chunkTask?.cancel()
                previewTask?.cancel()
                Self.logger.warning("Timed out while flushing final transcript chunks during stop; forcing completion")
            }
        } else {
            chunkTask?.cancel()
            previewTask?.cancel()
            let didFinish = await completeWithin(timeoutNanoseconds: transcriptionStopTimeoutNanoseconds) {
                await engine.stop(mode: .discardPendingWork)
            }
            if !didFinish {
                Self.logger.warning("Timed out while discarding transcript work during shutdown")
            }
        }
    }

    private func completeWithin(
        timeoutNanoseconds: UInt64,
        operation: @escaping @Sendable () async -> Void
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            var timeoutTask: Task<Void, Never>?

            func resume(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            let operationTask = Task {
                await operation()
                timeoutTask?.cancel()
                resume(true)
            }

            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                operationTask.cancel()
                resume(false)
            }
        }
    }

    private func sendState(status: TranscriptStatus) async {
        let message = TranscriptStateMessage(
            range: context.range,
            status: status,
            modelLabel: context.modelLabel,
            micDeviceLabel: context.micDeviceLabel,
            systemDeviceLabel: context.systemDeviceLabel
        )
        await MainActor.run {
            callbacks.state(message)
        }
    }

    private func sendLevel(source: TranscriptSource, level: Double) async {
        let message = TranscriptLevelUpdateMessage(
            range: context.range,
            source: source,
            level: level
        )
        await MainActor.run {
            callbacks.level(message)
        }
    }

    private func sendChunk(_ chunk: TranscriptChunk) async {
        guard !suppressOutput else {
            return
        }
        guard shouldEmitTranscriptText(chunk.text, source: chunk.source) else {
            return
        }
        let absoluteTimestamp = absoluteTimestamp(forAudioOffset: chunk.timestamp)
        let message = TranscriptChunkMessage(
            range: context.range,
            source: chunk.source,
            timestamp: absoluteTimestamp,
            text: lineFormatter.format(
                TranscriptChunk(
                    source: chunk.source,
                    timestamp: absoluteTimestamp,
                    text: chunk.text
                )
            )
        )
        await MainActor.run {
            callbacks.chunk(message)
        }
    }

    private func shouldEmitTranscriptText(_ text: String, source: TranscriptSource) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        let punctuationAndSymbols = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        let meaningfulScalars = trimmed.unicodeScalars.filter { !punctuationAndSymbols.contains($0) }
        guard !meaningfulScalars.isEmpty else {
            return false
        }

        guard source == .mic else {
            return true
        }

        if meaningfulScalars.count == 1 {
            return false
        }

        if meaningfulScalars.count == 2 {
            let hasLatinOrDigit = meaningfulScalars.contains { scalar in
                CharacterSet.alphanumerics.contains(scalar)
            }
            if !hasLatinOrDigit {
                return false
            }
        }

        return true
    }

    private func sendPreview(_ preview: TranscriptPreview) async {
        guard !suppressOutput else {
            return
        }
        let absoluteTimestamp = absoluteTimestamp(forAudioOffset: preview.timestamp)
        let message = TranscriptPreviewMessage(
            range: context.range,
            source: preview.source,
            timestamp: absoluteTimestamp,
            text: preview.text
        )
        await MainActor.run {
            callbacks.preview(message)
        }
    }

    private func sendError(_ message: String) async {
        let error = TranscriptErrorMessage(
            range: context.range,
            message: message
        )
        await MainActor.run {
            callbacks.error(error)
        }
    }

    private func sendModelDownloadProgress(
        fractionCompleted: Double,
        receivedBytes: Int,
        totalBytes: Int,
        stage: TranscriptDownloadStage
    ) async {
        let progress = TranscriptModelDownloadProgressMessage(
            range: context.range,
            modelLabel: context.modelLabel,
            progress: TranscriptDownloadProgress(
                fractionCompleted: fractionCompleted,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
                stage: stage
            )
        )
        await MainActor.run {
            callbacks.modelDownloadProgress(progress)
        }
    }

    private func clearModelDownloadProgress() async {
        await sendModelDownloadProgress(
            fractionCompleted: 0,
            receivedBytes: 0,
            totalBytes: 0,
            stage: .downloading
        )
    }

    private func beginRecordingTimelineSegment(at wallClock: Date) {
        let audioOffset = currentAudioOffset(at: wallClock)
        if let lastAnchor = recordingTimeline.last,
           abs(lastAnchor.audioOffset - audioOffset) < 0.001,
           abs(lastAnchor.wallClock.timeIntervalSince(wallClock)) < 0.001 {
            return
        }
        recordingTimeline.append(
            TranscriptTimelineAnchor(
                audioOffset: audioOffset,
                wallClock: wallClock
            )
        )
        activeRecordingWallClock = wallClock
    }

    private func closeRecordingTimelineSegment(at wallClock: Date) {
        guard activeRecordingWallClock != nil else {
            return
        }
        recordedAudioOffset = currentAudioOffset(at: wallClock)
        activeRecordingWallClock = nil
    }

    private func currentAudioOffset(at wallClock: Date) -> TimeInterval {
        guard let activeRecordingWallClock else {
            return recordedAudioOffset
        }
        return max(recordedAudioOffset, recordedAudioOffset + wallClock.timeIntervalSince(activeRecordingWallClock))
    }

    private func absoluteTimestamp(forAudioOffset audioOffset: TimeInterval) -> TimeInterval {
        guard !recordingTimeline.isEmpty else {
            return dateProvider().timeIntervalSince1970
        }
        let anchor = recordingTimeline.last(where: { $0.audioOffset <= audioOffset }) ?? recordingTimeline[0]
        return anchor.wallClock.addingTimeInterval(audioOffset - anchor.audioOffset).timeIntervalSince1970
    }
}

actor TranscriptLevelMonitor {
    private static let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "TranscriptLevelMonitor")
    private static let updateInterval: TimeInterval = 1.0 / 8.0
    private static let minimumLevelDelta: Double = 0.04

    private let range: TranscriptBlockRange
    private let micEnabled: Bool
    private let systemProcesses: [AudioProcessDescriptor]
    private let microphoneCapture: MicrophoneCapturing
    private let systemAudioCapture: SystemAudioCapturing?
    private let requestMicrophoneAccess: @Sendable () async throws -> Void
    private let sendLevelUpdate: @MainActor (TranscriptLevelUpdateMessage) -> Void
    private var isRunning = false
    private var lastMicLevel = 0.0
    private var lastSystemLevel = 0.0
    private var lastMicSentAt = 0.0
    private var lastSystemSentAt = 0.0

    init(
        range: TranscriptBlockRange,
        micEnabled: Bool,
        systemProcesses: [AudioProcessDescriptor],
        microphoneCapture: MicrophoneCapturing = MicrophoneCapture(),
        systemAudioCapture: SystemAudioCapturing? = SystemAudioCapture(),
        requestMicrophoneAccess: @escaping @Sendable () async throws -> Void = {
            try await MicrophoneCapture.requestAccessIfNeeded()
        },
        sendLevelUpdate: @escaping @MainActor (TranscriptLevelUpdateMessage) -> Void
    ) {
        self.range = range
        self.micEnabled = micEnabled
        self.systemProcesses = systemProcesses
        self.microphoneCapture = microphoneCapture
        self.systemAudioCapture = systemAudioCapture
        self.requestMicrophoneAccess = requestMicrophoneAccess
        self.sendLevelUpdate = sendLevelUpdate
    }

    func start() async {
        guard !isRunning else { return }
        if micEnabled {
            do {
                try await requestMicrophoneAccess()
            } catch {
                Self.logger.error("TranscriptLevelMonitor microphone access failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if micEnabled {
            do {
                try microphoneCapture.start { [weak self] buffer in
                    Task {
                        await self?.handleBuffer(source: .mic, buffer: buffer)
                    }
                }
            } catch {
                Self.logger.error("TranscriptLevelMonitor microphone start failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let systemAudioCapture, !systemProcesses.isEmpty {
            do {
                try systemAudioCapture.start(processes: systemProcesses) { [weak self] buffer in
                    Task {
                        await self?.handleBuffer(source: .system, buffer: buffer)
                    }
                }
            } catch {
                Self.logger.error("TranscriptLevelMonitor system start failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        isRunning = true
        await sendLevel(source: .mic, level: 0)
        await sendLevel(source: .system, level: 0)
    }

    func stop() async {
        guard isRunning else {
            await sendLevel(source: .mic, level: 0)
            await sendLevel(source: .system, level: 0)
            return
        }
        microphoneCapture.stop()
        systemAudioCapture?.stop()
        isRunning = false
        await sendLevel(source: .mic, level: 0)
        await sendLevel(source: .system, level: 0)
    }

    private func handleBuffer(source: TranscriptSource, buffer: AVAudioPCMBuffer) async {
        guard isRunning else { return }
        let level = AudioLevelMeter.normalizedLevel(for: buffer)
        let now = ProcessInfo.processInfo.systemUptime
        let lastSentAt = source == .mic ? lastMicSentAt : lastSystemSentAt
        let lastLevel = source == .mic ? lastMicLevel : lastSystemLevel
        let shouldSend = now - lastSentAt >= Self.updateInterval || abs(level - lastLevel) >= Self.minimumLevelDelta
        guard shouldSend else { return }
        await sendLevel(source: source, level: level)
    }

    private func sendLevel(source: TranscriptSource, level: Double) async {
        let now = ProcessInfo.processInfo.systemUptime
        if source == .mic {
            lastMicLevel = level
            lastMicSentAt = now
        } else {
            lastSystemLevel = level
            lastSystemSentAt = now
        }
        let message = TranscriptLevelUpdateMessage(
            range: range,
            source: source,
            level: level
        )
        await MainActor.run {
            sendLevelUpdate(message)
        }
    }
}

actor TranscriptSessionRegistry {
    static let shared = TranscriptSessionRegistry()

    private var activeSession: TranscriptSession?

    func start(_ session: TranscriptSession) async {
        if let activeSession {
            await activeSession.stop()
        }
        activeSession = session
        await session.start()
    }

    func pause(range: TranscriptBlockRange) async {
        _ = range
        guard let activeSession else {
            return
        }
        await activeSession.pause()
    }

    func resume(range: TranscriptBlockRange) async {
        _ = range
        guard let activeSession else {
            return
        }
        await activeSession.resume()
    }

    func stop(range: TranscriptBlockRange) async {
        _ = range
        guard let activeSession else {
            return
        }
        await activeSession.stop()
        self.activeSession = nil
    }

    func clear(range: TranscriptBlockRange) async {
        _ = range
        guard let activeSession else {
            return
        }
        await activeSession.clear()
        self.activeSession = nil
    }
}
