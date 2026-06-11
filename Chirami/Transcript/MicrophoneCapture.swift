import AudioToolbox
import AVFoundation
import Foundation
import OSLog

enum MicrophoneCaptureError: LocalizedError, Equatable {
    case alreadyRunning
    case permissionDenied
    case permissionRestricted
    case unableToCreateConverter
    case failedToStartEngine(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Microphone capture is already running."
        case .permissionDenied:
            return "Microphone access was denied."
        case .permissionRestricted:
            return "Microphone access is restricted."
        case .unableToCreateConverter:
            return "Failed to create an audio converter for microphone capture."
        case .failedToStartEngine(let underlying):
            return "Failed to start the microphone audio engine: \(underlying)"
        }
    }
}

final class MicrophoneCapture {
    typealias BufferHandler = @Sendable (AVAudioPCMBuffer) -> Void

    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "MicrophoneCapture")
    private let engine: AVAudioEngine
    private let tapBufferSize: AVAudioFrameCount
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var bufferHandler: BufferHandler?
    private var isRunning = false

    init(
        engine: AVAudioEngine = AVAudioEngine(),
        targetSampleRate: Double = 16_000,
        targetChannels: AVAudioChannelCount = 1,
        tapBufferSize: AVAudioFrameCount = 1024
    ) {
        self.engine = engine
        self.tapBufferSize = tapBufferSize
        self.targetFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: targetChannels)!
    }

    var outputFormat: AVAudioFormat {
        targetFormat
    }

    var running: Bool {
        isRunning
    }

    static func requestAccessIfNeeded() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            if granted {
                return
            }
            throw MicrophoneCaptureError.permissionDenied
        case .denied:
            throw MicrophoneCaptureError.permissionDenied
        case .restricted:
            throw MicrophoneCaptureError.permissionRestricted
        @unknown default:
            throw MicrophoneCaptureError.permissionDenied
        }
    }

    func start(deviceUID: String?, bufferHandler: @escaping BufferHandler) throws {
        guard !isRunning else {
            throw MicrophoneCaptureError.alreadyRunning
        }

        let inputNode = engine.inputNode
        configureInputDevice(deviceUID: deviceUID, on: inputNode)
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw MicrophoneCaptureError.unableToCreateConverter
        }

        self.converter = converter
        self.bufferHandler = bufferHandler

        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.process(inputBuffer: buffer)
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            inputNode.removeTap(onBus: 0)
            cleanup()
            throw MicrophoneCaptureError.failedToStartEngine(error.localizedDescription)
        }
    }

    func pause() {
        guard isRunning else {
            return
        }
        engine.pause()
    }

    func resume() throws {
        guard isRunning else {
            return
        }
        try engine.start()
    }

    func stop() {
        guard isRunning else {
            cleanup()
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        cleanup()
    }

    /// Routes the input node to the device identified by `deviceUID`.
    /// Falls back to the system default input device when `deviceUID` is nil
    /// or the device cannot be resolved.
    private func configureInputDevice(deviceUID: String?, on inputNode: AVAudioInputNode) {
        guard let deviceUID else {
            return
        }

        guard let deviceID = AudioDeviceEnumerator.audioDeviceID(forUID: deviceUID) else {
            logger.warning("Audio input device not found for UID \(deviceUID, privacy: .public); falling back to the system default input")
            return
        }

        guard let audioUnit = inputNode.audioUnit else {
            logger.warning("Input node audio unit is unavailable; falling back to the system default input")
            return
        }

        var currentDevice = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &currentDevice,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            logger.warning("Failed to set input device for UID \(deviceUID, privacy: .public) (status: \(status)); falling back to the system default input")
        }
    }

    private func process(inputBuffer: AVAudioPCMBuffer) {
        guard let converter, let bufferHandler else {
            return
        }

        let outputFrameCapacity = max(
            1,
            AVAudioFrameCount(
                ceil(Double(inputBuffer.frameLength) * targetFormat.sampleRate / inputBuffer.format.sampleRate)
            )
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }

        var conversionError: NSError?
        var providedInput = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outputStatus in
            if providedInput {
                outputStatus.pointee = .noDataNow
                return nil
            }

            providedInput = true
            outputStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, conversionError == nil else {
            return
        }
        guard outputBuffer.frameLength > 0 else {
            return
        }

        bufferHandler(outputBuffer)
    }

    private func cleanup() {
        isRunning = false
        converter = nil
        bufferHandler = nil
    }
}

extension MicrophoneCapture: MicrophoneCapturing {}
