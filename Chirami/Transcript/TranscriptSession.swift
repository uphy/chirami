import Foundation
import AVFoundation

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
    var micDeviceLabel: String
    var systemDeviceLabel: String
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
    _ progress: @escaping WhisperModelDownloadProgressHandler
) async throws -> TranscriptionEngine?

actor TranscriptSession {
    private let context: TranscriptSessionContext
    private let callbacks: TranscriptSessionCallbacks
    private let microphoneCapture: MicrophoneCapturing
    private let systemAudioCapture: SystemAudioCapturing?
    private let transcriptionEngineFactory: TranscriptTranscriptionEngineFactory?
    private let systemProcesses: [AudioProcessDescriptor]
    private let requestMicrophoneAccess: @Sendable () async throws -> Void

    private var status: TranscriptStatus = .idle
    private var chunkForwardingTask: Task<Void, Never>?
    private var previewForwardingTask: Task<Void, Never>?
    private var transcriptionEngine: TranscriptionEngine?
    private var transcriptionPreparationTask: Task<TranscriptionEngine?, Error>?
    private var isPreparingTranscriptionEngine = false
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
        }
    ) {
        self.context = context
        self.callbacks = callbacks
        self.microphoneCapture = microphoneCapture
        self.systemAudioCapture = systemAudioCapture
        self.transcriptionEngine = transcriptionEngine
        self.transcriptionEngineFactory = transcriptionEngineFactory
        self.systemProcesses = systemProcesses
        self.requestMicrophoneAccess = requestMicrophoneAccess
    }

    func start() async {
        guard status == .idle || status == .completed || status == .error else {
            return
        }

        do {
            try await requestMicrophoneAccess()
        } catch {
            await transitionToError(error.localizedDescription)
            return
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

        status = .recording
        await sendState(status: .recording)
        await sendLevel(source: .mic, level: 0)
        await sendLevel(source: .system, level: 0)
    }

    func pause() async {
        guard status == .recording else {
            return
        }

        microphoneCapture.pause()
        systemAudioCapture?.pause()
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
            try microphoneCapture.resume()
            try systemAudioCapture?.resume()
        } catch {
            await transitionToError(error.localizedDescription)
            return
        }

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

        microphoneCapture.stop()
        systemAudioCapture?.stop()
        await stopTranscriptionEngine(flushFinalChunks: true)
        status = .processing
        await sendState(status: .processing)
        await sendLevel(source: .mic, level: 0)
        await sendLevel(source: .system, level: 0)

        status = .completed
        await clearModelDownloadProgress()
        await sendState(status: .completed)
    }

    func clear() async {
        transcriptionPreparationTask?.cancel()
        transcriptionPreparationTask = nil
        isPreparingTranscriptionEngine = false
        microphoneCapture.stop()
        systemAudioCapture?.stop()
        await stopTranscriptionEngine(flushFinalChunks: false)
        status = .idle
        await clearModelDownloadProgress()
        await sendState(status: .idle)
        await sendLevel(source: .mic, level: 0)
        await sendLevel(source: .system, level: 0)
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
        transcriptionPreparationTask?.cancel()
        transcriptionPreparationTask = nil
        isPreparingTranscriptionEngine = false
        microphoneCapture.stop()
        systemAudioCapture?.stop()
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
            try await transcriptionEngineFactory { receivedBytes, totalBytes, fractionCompleted in
                Task {
                    await self.sendModelDownloadProgress(
                        fractionCompleted: min(max(fractionCompleted, 0), 1),
                        receivedBytes: max(0, Int(receivedBytes)),
                        totalBytes: max(0, Int(totalBytes ?? 0))
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
        if case .cancelledDownloadingModel = error as? WhisperModelStoreError {
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
            await engine.stop()
            _ = await chunkTask?.result
            _ = await previewTask?.result
        } else {
            chunkTask?.cancel()
            previewTask?.cancel()
            await engine.stop()
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
        let message = TranscriptChunkMessage(
            range: context.range,
            source: chunk.source,
            timestamp: chunk.timestamp,
            text: chunk.text
        )
        await MainActor.run {
            callbacks.chunk(message)
        }
    }

    private func sendPreview(_ preview: TranscriptPreview) async {
        let message = TranscriptPreviewMessage(
            range: context.range,
            source: preview.source,
            timestamp: preview.timestamp,
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
        totalBytes: Int
    ) async {
        let progress = TranscriptModelDownloadProgressMessage(
            range: context.range,
            modelLabel: context.modelLabel,
            progress: TranscriptDownloadProgress(
                fractionCompleted: fractionCompleted,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes
            )
        )
        await MainActor.run {
            callbacks.modelDownloadProgress(progress)
        }
    }

    private func clearModelDownloadProgress() async {
        await sendModelDownloadProgress(fractionCompleted: 0, receivedBytes: 0, totalBytes: 0)
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
