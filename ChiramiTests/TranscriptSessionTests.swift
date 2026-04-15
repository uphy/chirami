import AVFoundation
import CoreAudio
import Foundation
import Testing
@testable import Chirami

@MainActor
private final class TranscriptEventRecorder {
    var chunks: [TranscriptChunkMessage] = []
    var states: [TranscriptStateMessage] = []
    var levels: [TranscriptLevelUpdateMessage] = []
    var downloadProgress: [TranscriptModelDownloadProgressMessage] = []
    var errors: [TranscriptErrorMessage] = []
}

private final class MockMicrophoneCapture: MicrophoneCapturing {
    var onStart: ((@escaping @Sendable (AVAudioPCMBuffer) -> Void) -> Void)?
    var pauseCallCount = 0
    var resumeCallCount = 0
    var stopCallCount = 0

    func start(bufferHandler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        onStart?(bufferHandler)
    }

    func pause() {
        pauseCallCount += 1
    }

    func resume() throws {
        resumeCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }
}

private final class MockSystemAudioCapture: SystemAudioCapturing {
    var onStart: (([AudioProcessDescriptor], @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> Void)?
    var pauseCallCount = 0
    var resumeCallCount = 0
    var stopCallCount = 0

    func start(processes: [AudioProcessDescriptor], bufferHandler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        onStart?(processes, bufferHandler)
    }

    func pause() {
        pauseCallCount += 1
    }

    func resume() throws {
        resumeCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }
}

private final class MockTranscriptionEngine: TranscriptionEngine {
    private let chunkStream: AsyncStream<TranscriptChunk>
    private let continuation: AsyncStream<TranscriptChunk>.Continuation
    private let previewStream: AsyncStream<TranscriptPreview>
    private let previewContinuation: AsyncStream<TranscriptPreview>.Continuation

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var fedSources: [TranscriptSource] = []
    private(set) var audioFormats: [AVAudioFormat] = []
    var onStop: (() -> Void)?

    init() {
        var streamContinuation: AsyncStream<TranscriptChunk>.Continuation?
        self.chunkStream = AsyncStream { continuation in
            streamContinuation = continuation
        }
        self.continuation = streamContinuation!
        var streamPreviewContinuation: AsyncStream<TranscriptPreview>.Continuation?
        self.previewStream = AsyncStream { continuation in
            streamPreviewContinuation = continuation
        }
        self.previewContinuation = streamPreviewContinuation!
    }

    var chunks: AsyncStream<TranscriptChunk> {
        chunkStream
    }

    var previews: AsyncStream<TranscriptPreview> {
        previewStream
    }

    func start(audioFormat: AVAudioFormat) async throws {
        startCallCount += 1
        audioFormats.append(audioFormat)
    }

    func feed(buffer: AVAudioPCMBuffer, source: TranscriptSource) async throws {
        _ = buffer
        fedSources.append(source)
    }

    func stop() async {
        stopCallCount += 1
        onStop?()
        continuation.finish()
        previewContinuation.finish()
    }

    func yield(_ chunk: TranscriptChunk) {
        continuation.yield(chunk)
    }

    func yield(_ preview: TranscriptPreview) {
        previewContinuation.yield(preview)
    }
}

@Suite("Transcript session")
struct TranscriptSessionTests {
    @Test("start emits recording state and forwards mic/system levels")
    func startEmitsRecordingStateAndLevels() async {
        let recorder = TranscriptEventRecorder()
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendChunk = { recorder.chunks.append($0) }
        callbacks.sendState = { recorder.states.append($0) }
        callbacks.sendLevel = { recorder.levels.append($0) }
        callbacks.sendModelDownloadProgress = { recorder.downloadProgress.append($0) }
        callbacks.sendError = { recorder.errors.append($0) }

        let micCapture = MockMicrophoneCapture()
        let systemCapture = MockSystemAudioCapture()
        let transcriptionEngine = MockTranscriptionEngine()
        let context = TranscriptSessionContext(
            range: TranscriptBlockRange(blockFrom: 10, blockTo: 20),
            modelLabel: "test-model",
            micDeviceLabel: "Default",
            systemDeviceLabel: "Zoom"
        )
        let process = AudioProcessDescriptor(
            objectID: 1,
            pid: 42,
            bundleID: "us.zoom.xos",
            applicationName: "Zoom",
            isRunningInput: false,
            isRunningOutput: true
        )

        var micHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?
        micCapture.onStart = { handler in
            micHandler = handler
        }

        var systemHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?
        systemCapture.onStart = { _, handler in
            systemHandler = handler
        }

        let session = TranscriptSession(
            context: context,
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: systemCapture,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [process],
            requestMicrophoneAccess: {}
        )

        await session.start()

        #expect(recorder.states.last?.status == .recording)
        #expect(recorder.errors.isEmpty)
        #expect(micHandler != nil)
        #expect(systemHandler != nil)

        micHandler?(makeBuffer(samples: [0.2, -0.2, 0.4, -0.4]))
        systemHandler?(makeBuffer(samples: [0.6, -0.6, 0.6, -0.6]))
        transcriptionEngine.yield(
            TranscriptChunk(source: .mic, timestamp: 1.25, text: "hello world")
        )

        await Task.yield()

        let micLevels = recorder.levels.filter { $0.source == .mic }.map(\.level)
        let systemLevels = recorder.levels.filter { $0.source == .system }.map(\.level)
        #expect(micLevels.contains(where: { $0 > 0 }))
        #expect(systemLevels.contains(where: { $0 > 0 }))
        #expect(transcriptionEngine.startCallCount == 1)
        #expect(transcriptionEngine.fedSources == [.mic, .system])
        #expect(recorder.chunks.last?.text == "hello world")
        #expect(recorder.chunks.last?.timestamp == 1.25)
    }

    @Test("pause resume and stop control captures and emit states")
    func pauseResumeAndStopControlCaptures() async {
        let recorder = TranscriptEventRecorder()
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendChunk = { recorder.chunks.append($0) }
        callbacks.sendState = { recorder.states.append($0) }
        callbacks.sendLevel = { recorder.levels.append($0) }
        callbacks.sendModelDownloadProgress = { recorder.downloadProgress.append($0) }
        callbacks.sendError = { recorder.errors.append($0) }

        let micCapture = MockMicrophoneCapture()
        let systemCapture = MockSystemAudioCapture()
        let transcriptionEngine = MockTranscriptionEngine()
        let context = TranscriptSessionContext(
            range: TranscriptBlockRange(blockFrom: 1, blockTo: 2),
            modelLabel: "test-model",
            micDeviceLabel: "Default",
            systemDeviceLabel: "Off"
        )

        let session = TranscriptSession(
            context: context,
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: systemCapture,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {}
        )

        await session.start()
        await session.pause()
        await session.resume()
        await session.stop()

        #expect(micCapture.pauseCallCount == 1)
        #expect(micCapture.resumeCallCount == 1)
        #expect(micCapture.stopCallCount == 1)
        #expect(systemCapture.pauseCallCount == 1)
        #expect(systemCapture.resumeCallCount == 1)
        #expect(systemCapture.stopCallCount == 1)
        #expect(transcriptionEngine.stopCallCount == 1)

        let statuses = recorder.states.map(\.status)
        #expect(statuses == [.recording, .paused, .recording, .processing, .completed])
        let finalLevels = recorder.levels.suffix(2).map(\.level)
        #expect(finalLevels.allSatisfy { $0 == 0 })
    }

    @Test("stop flushes final chunks before completing")
    func stopFlushesFinalChunksBeforeCompleting() async {
        let recorder = TranscriptEventRecorder()
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendChunk = { recorder.chunks.append($0) }
        callbacks.sendState = { recorder.states.append($0) }
        callbacks.sendLevel = { recorder.levels.append($0) }
        callbacks.sendModelDownloadProgress = { recorder.downloadProgress.append($0) }
        callbacks.sendError = { recorder.errors.append($0) }

        let micCapture = MockMicrophoneCapture()
        let transcriptionEngine = MockTranscriptionEngine()
        transcriptionEngine.onStop = {
            transcriptionEngine.yield(
                TranscriptChunk(source: .mic, timestamp: 2.5, text: "final chunk")
            )
        }

        let session = TranscriptSession(
            context: TranscriptSessionContext(
                range: TranscriptBlockRange(blockFrom: 1, blockTo: 2),
                modelLabel: "test-model",
                micDeviceLabel: "Default",
                systemDeviceLabel: "Off"
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {}
        )

        await session.start()
        await session.stop()

        #expect(recorder.chunks.last?.text == "final chunk")
        #expect(recorder.states.last?.status == .completed)
    }

    @Test("permission failure transitions to error without starting capture")
    func permissionFailureTransitionsToError() async {
        let recorder = TranscriptEventRecorder()
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendChunk = { recorder.chunks.append($0) }
        callbacks.sendState = { recorder.states.append($0) }
        callbacks.sendLevel = { recorder.levels.append($0) }
        callbacks.sendModelDownloadProgress = { recorder.downloadProgress.append($0) }
        callbacks.sendError = { recorder.errors.append($0) }

        let micCapture = MockMicrophoneCapture()
        let transcriptionEngine = MockTranscriptionEngine()
        let session = TranscriptSession(
            context: TranscriptSessionContext(
                range: TranscriptBlockRange(blockFrom: 1, blockTo: 2),
                modelLabel: "test-model",
                micDeviceLabel: "Default",
                systemDeviceLabel: "Off"
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {
                throw MicrophoneCaptureError.permissionDenied
            }
        )

        await session.start()

        #expect(recorder.states.last?.status == .error)
        #expect(recorder.errors.last?.message == MicrophoneCaptureError.permissionDenied.localizedDescription)
        #expect(micCapture.stopCallCount == 1)
        #expect(transcriptionEngine.startCallCount == 0)
    }

    @Test("model download progress is emitted before recording starts")
    func modelDownloadProgressIsEmittedBeforeRecordingStarts() async {
        let recorder = TranscriptEventRecorder()
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendChunk = { recorder.chunks.append($0) }
        callbacks.sendState = { recorder.states.append($0) }
        callbacks.sendLevel = { recorder.levels.append($0) }
        callbacks.sendModelDownloadProgress = { recorder.downloadProgress.append($0) }
        callbacks.sendError = { recorder.errors.append($0) }

        let micCapture = MockMicrophoneCapture()
        var micStartCount = 0
        micCapture.onStart = { _ in
            micStartCount += 1
        }

        let downloadedEngine = MockTranscriptionEngine()
        let session = TranscriptSession(
            context: TranscriptSessionContext(
                range: TranscriptBlockRange(blockFrom: 3, blockTo: 4),
                modelLabel: "test-model",
                micDeviceLabel: "Default",
                systemDeviceLabel: "Off"
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngineFactory: { progress in
                progress(256, 1024, 0.25)
                progress(1024, 1024, 1)
                return downloadedEngine
            },
            systemProcesses: [],
            requestMicrophoneAccess: {}
        )

        await session.start()
        await Task.yield()

        #expect(recorder.states.map(\.status) == [.processing, .recording])
        #expect(recorder.downloadProgress.count >= 3)
        #expect(recorder.downloadProgress[0].progress.fractionCompleted == 0.25)
        #expect(recorder.downloadProgress[0].progress.receivedBytes == 256)
        #expect(recorder.downloadProgress[0].progress.totalBytes == 1024)
        #expect(recorder.downloadProgress[1].progress.fractionCompleted == 1)
        #expect(recorder.downloadProgress[1].progress.receivedBytes == 1024)
        #expect(recorder.downloadProgress[1].progress.totalBytes == 1024)
        #expect(recorder.downloadProgress.last?.progress.fractionCompleted == 0)
        #expect(recorder.downloadProgress.last?.progress.receivedBytes == 0)
        #expect(recorder.downloadProgress.last?.progress.totalBytes == 0)
        #expect(downloadedEngine.startCallCount == 1)
        #expect(micStartCount == 1)
        #expect(recorder.errors.isEmpty)
    }

    private func makeBuffer(samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            guard let channelData = buffer.floatChannelData else {
                return
            }
            channelData[0].assign(from: pointer.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
