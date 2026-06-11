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

private final class MutableDateBox: @unchecked Sendable {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

private final class MockMicrophoneCapture: MicrophoneCapturing {
    var onStart: ((@escaping @Sendable (AVAudioPCMBuffer) -> Void) -> Void)?
    var startedDeviceUIDs: [String?] = []
    var pauseCallCount = 0
    var resumeCallCount = 0
    var stopCallCount = 0

    func start(deviceUID: String?, bufferHandler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        startedDeviceUIDs.append(deviceUID)
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

    // `feed` can run concurrently for mic/system buffers (actor reentrancy
    // in TranscriptSession), so guard mutable state with a lock.
    private let lock = NSLock()
    private var _startCallCount = 0
    private var _stopCallCount = 0
    private var _stopModes: [TranscriptionEngineStopMode] = []
    private var _fedSources: [TranscriptSource] = []
    private var _audioFormats: [AVAudioFormat] = []
    var onStop: (() -> Void)?

    var startCallCount: Int {
        lock.withLock { _startCallCount }
    }

    var stopCallCount: Int {
        lock.withLock { _stopCallCount }
    }

    var stopModes: [TranscriptionEngineStopMode] {
        lock.withLock { _stopModes }
    }

    var fedSources: [TranscriptSource] {
        lock.withLock { _fedSources }
    }

    var audioFormats: [AVAudioFormat] {
        lock.withLock { _audioFormats }
    }

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
        lock.withLock {
            _startCallCount += 1
            _audioFormats.append(audioFormat)
        }
    }

    func feed(buffer: AVAudioPCMBuffer, source: TranscriptSource) async throws {
        _ = buffer
        lock.withLock {
            _fedSources.append(source)
        }
    }

    func stop(mode: TranscriptionEngineStopMode) async {
        lock.withLock {
            _stopCallCount += 1
            _stopModes.append(mode)
        }
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

private final class HangingStopTranscriptionEngine: TranscriptionEngine {
    var chunks: AsyncStream<TranscriptChunk> { AsyncStream { _ in } }
    var previews: AsyncStream<TranscriptPreview> { AsyncStream { _ in } }

    private(set) var stopModes: [TranscriptionEngineStopMode] = []

    func start(audioFormat: AVAudioFormat) async throws {
        _ = audioFormat
    }

    func feed(buffer: AVAudioPCMBuffer, source: TranscriptSource) async throws {
        _ = buffer
        _ = source
    }

    func stop(mode: TranscriptionEngineStopMode) async {
        stopModes.append(mode)
        // Hang until the caller's stop timeout cancels this task.
        // Task.sleep is cancellation-aware, so the task exits cleanly
        // instead of leaking a never-resumed continuation.
        try? await Task.sleep(nanoseconds: 60_000_000_000)
    }
}

@Suite("Transcript session")
@MainActor
struct TranscriptSessionTests {
    @Test("start emits recording state and forwards mic/system levels")
    func startEmitsRecordingStateAndLevels() async {
        let fixedDate = Date(timeIntervalSince1970: 1_776_340_800)
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
            micEnabled: true,
            micDeviceLabel: "Default",
            systemDeviceLabel: "Zoom",
            labels: TranscriptLabelConfig(mic: "You", system: "Others")
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
            requestMicrophoneAccess: {},
            dateProvider: { fixedDate },
            timeZone: TimeZone(secondsFromGMT: 0)!
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

        await waitUntil {
            transcriptionEngine.fedSources.count == 2 && !recorder.chunks.isEmpty
        }

        let micLevels = recorder.levels.filter { $0.source == .mic }.map(\.level)
        let systemLevels = recorder.levels.filter { $0.source == .system }.map(\.level)
        #expect(micLevels.contains(where: { $0 > 0 }))
        #expect(systemLevels.contains(where: { $0 > 0 }))
        #expect(transcriptionEngine.startCallCount == 1)
        // The mic/system buffer handlers run as independent tasks, so the
        // feed order is not deterministic.
        #expect(Set(transcriptionEngine.fedSources) == [.mic, .system])
        #expect(recorder.chunks.last?.text == "[2026-04-16 12:00:01] You: hello world")
        #expect(recorder.chunks.last?.timestamp == fixedDate.timeIntervalSince1970 + 1.25)
    }

    @Test("pause resume and stop control captures and emit states")
    func pauseResumeAndStopControlCaptures() async {
        let fixedDate = Date(timeIntervalSince1970: 1_776_340_800)
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
            micEnabled: true,
            micDeviceLabel: "Default",
            systemDeviceLabel: "Off",
            labels: TranscriptLabelConfig(mic: "You", system: "Others")
        )

        let session = TranscriptSession(
            context: context,
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: systemCapture,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {},
            dateProvider: { fixedDate },
            timeZone: TimeZone(secondsFromGMT: 0)!
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
        #expect(transcriptionEngine.stopModes == [.flushFinalChunks])

        let statuses = recorder.states.map(\.status)
        #expect(statuses == [.recording, .paused, .recording, .processing, .completed])
        let finalLevels = recorder.levels.suffix(2).map(\.level)
        #expect(finalLevels.allSatisfy { $0 == 0 })
    }

    @Test("chunk timestamps preserve wall clock across pause and resume")
    func chunkTimestampsPreserveWallClockAcrossPauseAndResume() async {
        let startDate = Date(timeIntervalSince1970: 1_776_340_800)
        let dateBox = MutableDateBox(startDate)
        let recorder = TranscriptEventRecorder()
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendChunk = { recorder.chunks.append($0) }
        callbacks.sendState = { recorder.states.append($0) }
        callbacks.sendLevel = { recorder.levels.append($0) }

        let micCapture = MockMicrophoneCapture()
        let transcriptionEngine = MockTranscriptionEngine()
        let session = TranscriptSession(
            context: TranscriptSessionContext(
                range: TranscriptBlockRange(blockFrom: 1, blockTo: 2),
                modelLabel: "test-model",
                micEnabled: true,
                micDeviceLabel: "Default",
                systemDeviceLabel: "Off",
                labels: TranscriptLabelConfig(mic: "You", system: "Others")
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {},
            dateProvider: { dateBox.date },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        await session.start()
        dateBox.date = startDate.addingTimeInterval(5)
        await session.pause()
        dateBox.date = startDate.addingTimeInterval(15)
        await session.resume()
        transcriptionEngine.yield(
            TranscriptChunk(source: .mic, timestamp: 6, text: "after resume")
        )
        await waitUntil { !recorder.chunks.isEmpty }

        #expect(recorder.chunks.last?.timestamp == startDate.addingTimeInterval(16).timeIntervalSince1970)
        #expect(recorder.chunks.last?.text == "[2026-04-16 12:00:16] You: after resume")
    }

    @Test("clear discards pending transcription work")
    func clearDiscardsPendingTranscriptionWork() async {
        let fixedDate = Date(timeIntervalSince1970: 1_776_340_800)
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
                TranscriptChunk(source: .mic, timestamp: 3.5, text: "should be dropped")
            )
        }

        let session = TranscriptSession(
            context: TranscriptSessionContext(
                range: TranscriptBlockRange(blockFrom: 5, blockTo: 6),
                modelLabel: "test-model",
                micEnabled: true,
                micDeviceLabel: "Default",
                systemDeviceLabel: "Off",
                labels: TranscriptLabelConfig(mic: "You", system: "Others")
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {},
            dateProvider: { fixedDate },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        await session.start()
        await session.clear()
        await Task.yield()

        #expect(recorder.chunks.isEmpty)
        #expect(recorder.states.last?.status == .idle)
        #expect(transcriptionEngine.stopModes == [.discardPendingWork])
    }

    @Test("drops punctuation-only mic chunks")
    func dropsPunctuationOnlyMicChunks() async {
        let fixedDate = Date(timeIntervalSince1970: 1_776_340_800)
        let recorder = TranscriptEventRecorder()
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendChunk = { recorder.chunks.append($0) }
        callbacks.sendState = { recorder.states.append($0) }
        callbacks.sendLevel = { recorder.levels.append($0) }

        let micCapture = MockMicrophoneCapture()
        let transcriptionEngine = MockTranscriptionEngine()
        let session = TranscriptSession(
            context: TranscriptSessionContext(
                range: TranscriptBlockRange(blockFrom: 1, blockTo: 2),
                modelLabel: "test-model",
                micEnabled: true,
                micDeviceLabel: "Default",
                systemDeviceLabel: "Off",
                labels: TranscriptLabelConfig(mic: "You", system: "Others")
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {},
            dateProvider: { fixedDate },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        await session.start()
        transcriptionEngine.yield(
            TranscriptChunk(source: .mic, timestamp: 1, text: "。")
        )
        transcriptionEngine.yield(
            TranscriptChunk(source: .mic, timestamp: 2, text: "こ。")
        )
        await Task.yield()

        #expect(recorder.chunks.isEmpty)
    }

    @Test("keeps normal others chunks")
    func keepsNormalOthersChunks() async {
        let fixedDate = Date(timeIntervalSince1970: 1_776_340_800)
        let recorder = TranscriptEventRecorder()
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendChunk = { recorder.chunks.append($0) }
        callbacks.sendState = { recorder.states.append($0) }
        callbacks.sendLevel = { recorder.levels.append($0) }

        let micCapture = MockMicrophoneCapture()
        let transcriptionEngine = MockTranscriptionEngine()
        let session = TranscriptSession(
            context: TranscriptSessionContext(
                range: TranscriptBlockRange(blockFrom: 1, blockTo: 2),
                modelLabel: "test-model",
                micEnabled: true,
                micDeviceLabel: "Default",
                systemDeviceLabel: "Off",
                labels: TranscriptLabelConfig(mic: "You", system: "Others")
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {},
            dateProvider: { fixedDate },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        await session.start()
        transcriptionEngine.yield(
            TranscriptChunk(source: .system, timestamp: 1, text: "了解しました。")
        )
        await waitUntil { !recorder.chunks.isEmpty }

        #expect(recorder.chunks.count == 1)
        #expect(recorder.chunks.last?.text == "[2026-04-16 12:00:01] Others: 了解しました。")
    }

    @Test("stop flushes final chunks before completing")
    func stopFlushesFinalChunksBeforeCompleting() async {
        let fixedDate = Date(timeIntervalSince1970: 1_776_340_800)
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
                micEnabled: true,
                micDeviceLabel: "Default",
                systemDeviceLabel: "Off",
                labels: TranscriptLabelConfig(mic: "You", system: "Others")
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {},
            dateProvider: { fixedDate },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        await session.start()
        await session.stop()

        #expect(recorder.chunks.last?.text == "[2026-04-16 12:00:02] You: final chunk")
        #expect(recorder.states.last?.status == .completed)
    }

    @Test("stop completes even when transcription engine flush hangs")
    func stopCompletesEvenWhenTranscriptionEngineFlushHangs() async {
        let fixedDate = Date(timeIntervalSince1970: 1_776_340_800)
        let recorder = TranscriptEventRecorder()
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendState = { recorder.states.append($0) }
        callbacks.sendLevel = { recorder.levels.append($0) }

        let micCapture = MockMicrophoneCapture()
        let hangingEngine = HangingStopTranscriptionEngine()
        let session = TranscriptSession(
            context: TranscriptSessionContext(
                range: TranscriptBlockRange(blockFrom: 1, blockTo: 2),
                modelLabel: "test-model",
                micEnabled: true,
                micDeviceLabel: "Default",
                systemDeviceLabel: "Off",
                labels: TranscriptLabelConfig(mic: "You", system: "Others")
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngine: hangingEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {},
            dateProvider: { fixedDate },
            timeZone: TimeZone(secondsFromGMT: 0)!,
            transcriptionStopTimeoutNanoseconds: 1_000_000
        )

        await session.start()
        await session.stop()

        #expect(hangingEngine.stopModes == [.flushFinalChunks])
        #expect(recorder.states.map(\.status) == [.recording, .processing, .completed])
    }

    @Test("permission failure transitions to error without starting capture")
    func permissionFailureTransitionsToError() async {
        let fixedDate = Date(timeIntervalSince1970: 1_776_340_800)
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
                micEnabled: true,
                micDeviceLabel: "Default",
                systemDeviceLabel: "Off",
                labels: TranscriptLabelConfig(mic: "You", system: "Others")
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {
                throw MicrophoneCaptureError.permissionDenied
            },
            dateProvider: { fixedDate },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        await session.start()

        #expect(recorder.states.last?.status == .error)
        #expect(recorder.errors.last?.message == MicrophoneCaptureError.permissionDenied.localizedDescription)
        #expect(micCapture.stopCallCount == 1)
        #expect(transcriptionEngine.startCallCount == 0)
    }

    @Test("model download progress is emitted before recording starts")
    func modelDownloadProgressIsEmittedBeforeRecordingStarts() async {
        let fixedDate = Date(timeIntervalSince1970: 1_776_340_800)
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
                micEnabled: true,
                micDeviceLabel: "Default",
                systemDeviceLabel: "Off",
                labels: TranscriptLabelConfig(mic: "You", system: "Others")
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngineFactory: { progress in
                progress(256, 1024, 0.25, .downloading)
                progress(1024, 1024, 1, .preparing)
                return downloadedEngine
            },
            systemProcesses: [],
            requestMicrophoneAccess: {},
            dateProvider: { fixedDate },
            timeZone: TimeZone(secondsFromGMT: 0)!
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

    @Test("resolved mic device UID reaches the microphone capture")
    func resolvedMicDeviceUIDReachesMicrophoneCapture() async {
        let fixedDate = Date(timeIntervalSince1970: 1_776_340_800)
        let recorder = TranscriptEventRecorder()
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendState = { recorder.states.append($0) }
        callbacks.sendLevel = { recorder.levels.append($0) }
        callbacks.sendError = { recorder.errors.append($0) }

        let micCapture = MockMicrophoneCapture()
        let transcriptionEngine = MockTranscriptionEngine()
        let resolved = TranscriptDeviceResolver.resolveMicSelection(
            blockSelection: TranscriptDeviceSnapshot(value: "mic-1", label: "USB Mic"),
            configuredValue: "default",
            availableDevices: [AudioDeviceDescriptor(uniqueID: "mic-1", name: "USB Mic")],
            defaultDevice: nil
        )
        let session = TranscriptSession(
            context: TranscriptSessionContext(
                range: TranscriptBlockRange(blockFrom: 1, blockTo: 2),
                modelLabel: "test-model",
                micEnabled: resolved.value != "off",
                micDeviceLabel: resolved.label,
                micDeviceUniqueID: TranscriptDeviceResolver.micDeviceUniqueID(from: resolved),
                systemDeviceLabel: "Off",
                labels: TranscriptLabelConfig(mic: "You", system: "Others")
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {},
            dateProvider: { fixedDate },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        await session.start()

        #expect(resolved.value == "mic-1")
        #expect(micCapture.startedDeviceUIDs == ["mic-1"])
        #expect(recorder.states.last?.status == .recording)
        #expect(recorder.errors.isEmpty)
    }

    @Test("default mic selection starts capture with the system default device")
    func defaultMicSelectionStartsCaptureWithSystemDefaultDevice() async {
        let fixedDate = Date(timeIntervalSince1970: 1_776_340_800)
        let recorder = TranscriptEventRecorder()
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendState = { recorder.states.append($0) }
        callbacks.sendLevel = { recorder.levels.append($0) }
        callbacks.sendError = { recorder.errors.append($0) }

        let micCapture = MockMicrophoneCapture()
        let transcriptionEngine = MockTranscriptionEngine()
        let resolved = TranscriptDeviceResolver.resolveMicSelection(
            blockSelection: TranscriptDeviceSnapshot(value: "default", label: "Default"),
            configuredValue: "default",
            availableDevices: [],
            defaultDevice: AudioDeviceDescriptor(uniqueID: "builtin-mic", name: "Built-in Microphone")
        )
        let session = TranscriptSession(
            context: TranscriptSessionContext(
                range: TranscriptBlockRange(blockFrom: 1, blockTo: 2),
                modelLabel: "test-model",
                micEnabled: resolved.value != "off",
                micDeviceLabel: resolved.label,
                micDeviceUniqueID: TranscriptDeviceResolver.micDeviceUniqueID(from: resolved),
                systemDeviceLabel: "Off",
                labels: TranscriptLabelConfig(mic: "You", system: "Others")
            ),
            callbacks: callbacks,
            microphoneCapture: micCapture,
            systemAudioCapture: nil,
            transcriptionEngine: transcriptionEngine,
            systemProcesses: [],
            requestMicrophoneAccess: {},
            dateProvider: { fixedDate },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        await session.start()

        #expect(resolved.value == "default")
        #expect(micCapture.startedDeviceUIDs == [nil])
        #expect(recorder.errors.isEmpty)
    }

    /// Polls `condition` until it becomes true or `timeout` elapses.
    /// The test suite runs on the main actor, so a bare `Task.yield()` is not
    /// enough for pipelines that hop through other actors and back to the main
    /// actor (buffer handler Task -> session actor -> MainActor.run callback).
    /// Sleeping releases the main actor and lets those hops complete.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
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
