import AVFoundation
import CoreAudio
import Foundation
import os

enum SystemAudioCaptureError: LocalizedError, Equatable {
    case unsupportedOS
    case alreadyRunning
    case unableToCreateTap(OSStatus)
    case unableToReadTapFormat(OSStatus)
    case unableToReadTapUID(OSStatus)
    case invalidTapFormat
    case unableToCreateAggregateDevice(OSStatus)
    case unableToConfigureAggregateDevice(OSStatus)
    case unableToCreateIOProc(OSStatus)
    case failedToStartDevice(OSStatus)
    case unableToCreateConverter

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "System audio capture requires macOS 14.2 or later."
        case .alreadyRunning:
            return "System audio capture is already running."
        case .unableToCreateTap(let status):
            return "Failed to create system audio tap (OSStatus \(status))."
        case .unableToReadTapFormat(let status):
            return "Failed to read the tap format (OSStatus \(status))."
        case .unableToReadTapUID(let status):
            return "Failed to read the tap UID (OSStatus \(status))."
        case .invalidTapFormat:
            return "The system audio tap returned an invalid PCM format."
        case .unableToCreateAggregateDevice(let status):
            return "Failed to create the aggregate capture device (OSStatus \(status))."
        case .unableToConfigureAggregateDevice(let status):
            return "Failed to configure the aggregate capture device (OSStatus \(status))."
        case .unableToCreateIOProc(let status):
            return "Failed to register the aggregate device IO callback (OSStatus \(status))."
        case .failedToStartDevice(let status):
            return "Failed to start the aggregate capture device (OSStatus \(status))."
        case .unableToCreateConverter:
            return "Failed to create an audio converter for system audio capture."
        }
    }
}

final class SystemAudioCapture {
    typealias BufferHandler = @Sendable (AVAudioPCMBuffer) -> Void
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "Transcript")

    private enum AggregateDescriptionKey {
        static let uid = "uid"
        static let name = "name"
        static let isPrivate = "private"
        static let tapList = "taps"
        static let tapAutoStart = "tapautostart"
    }

    private enum SubTapDescriptionKey {
        static let uid = "uid"
        static let driftCompensation = "drift"
    }

    private let ioQueue: DispatchQueue
    private let targetFormat: AVAudioFormat

    private var tapID: AudioObjectID?
    private var aggregateDeviceID: AudioObjectID?
    private var ioProcID: AudioDeviceIOProcID?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var bufferHandler: BufferHandler?
    private(set) var selectedProcesses: [AudioProcessDescriptor] = []
    private var isRunning = false
    private var isPaused = false

    init(
        targetSampleRate: Double = 16_000,
        targetChannels: AVAudioChannelCount = 1,
        ioQueue: DispatchQueue = DispatchQueue(label: "io.github.uphy.Chirami.SystemAudioCapture")
    ) {
        self.ioQueue = ioQueue
        self.targetFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: targetChannels)!
    }

    deinit {
        stop()
    }

    var outputFormat: AVAudioFormat {
        targetFormat
    }

    var running: Bool {
        isRunning
    }

    var paused: Bool {
        isPaused
    }

    func start(
        processes: [AudioProcessDescriptor],
        bufferHandler: @escaping BufferHandler
    ) throws {
        guard #available(macOS 14.2, *) else {
            throw SystemAudioCaptureError.unsupportedOS
        }
        guard !isRunning else {
            throw SystemAudioCaptureError.alreadyRunning
        }

        guard !processes.isEmpty else {
            return
        }

        logger.info("SystemAudioCapture start processes=\(processes.map(\.pid).description, privacy: .public)")

        let tapDescription = CATapDescription()
        tapDescription.processes = processes.map(\.objectID)
        tapDescription.name = "Chirami System Audio"
        tapDescription.uuid = UUID()
        tapDescription.isPrivate = true
        tapDescription.isExclusive = false
        tapDescription.isMixdown = true
        tapDescription.isMono = false
        tapDescription.muteBehavior = .unmuted

        var createdTapID = AudioObjectID()
        let createTapStatus = AudioHardwareCreateProcessTap(tapDescription, &createdTapID)
        guard createTapStatus == noErr else {
            throw SystemAudioCaptureError.unableToCreateTap(createTapStatus)
        }

        do {
            let tapFormat = try readTapFormat(tapID: createdTapID)
            let tapUID = try readTapUID(tapID: createdTapID)
            guard let converter = AVAudioConverter(from: tapFormat, to: targetFormat) else {
                throw SystemAudioCaptureError.unableToCreateConverter
            }

            let aggregateDeviceID = try createAggregateDevice(tapUID: tapUID)
            var createdIOProcID: AudioDeviceIOProcID?
            let createIOProcStatus = AudioDeviceCreateIOProcIDWithBlock(
                &createdIOProcID,
                aggregateDeviceID,
                ioQueue
            ) { [weak self] _, inputData, _, _, _ in
                self?.handleInputData(inputData)
            }
            guard createIOProcStatus == noErr, let createdIOProcID else {
                throw SystemAudioCaptureError.unableToCreateIOProc(createIOProcStatus)
            }

            let startStatus = AudioDeviceStart(aggregateDeviceID, createdIOProcID)
            guard startStatus == noErr else {
                AudioDeviceDestroyIOProcID(aggregateDeviceID, createdIOProcID)
                throw SystemAudioCaptureError.failedToStartDevice(startStatus)
            }

            self.tapID = createdTapID
            self.aggregateDeviceID = aggregateDeviceID
            self.ioProcID = createdIOProcID
            self.sourceFormat = tapFormat
            self.converter = converter
            self.bufferHandler = bufferHandler
            self.selectedProcesses = processes
            self.isRunning = true
            self.isPaused = false
        } catch {
            AudioHardwareDestroyProcessTap(createdTapID)
            throw error
        }
    }

    func pause() {
        guard isRunning, !isPaused, let aggregateDeviceID, let ioProcID else {
            return
        }
        AudioDeviceStop(aggregateDeviceID, ioProcID)
        isPaused = true
    }

    func resume() throws {
        guard isRunning, isPaused, let aggregateDeviceID, let ioProcID else {
            return
        }
        let status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            throw SystemAudioCaptureError.failedToStartDevice(status)
        }
        isPaused = false
    }

    func stop() {
        if let aggregateDeviceID, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        if let aggregateDeviceID {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if #available(macOS 14.2, *), let tapID {
            AudioHardwareDestroyProcessTap(tapID)
        }
        cleanup()
    }

    @available(macOS 14.2, *)
    private func createAggregateDevice(tapUID: String) throws -> AudioObjectID {
        let aggregateUID = UUID().uuidString
        let tapDescription: [String: Any] = [
            SubTapDescriptionKey.uid: tapUID,
            SubTapDescriptionKey.driftCompensation: 0
        ]
        let description: [String: Any] = [
            AggregateDescriptionKey.uid: aggregateUID,
            AggregateDescriptionKey.name: "Chirami System Audio Capture",
            AggregateDescriptionKey.isPrivate: 1,
            AggregateDescriptionKey.tapList: [tapDescription],
            AggregateDescriptionKey.tapAutoStart: 1
        ]

        var deviceID = AudioObjectID()
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)
        guard status == noErr else {
            throw SystemAudioCaptureError.unableToCreateAggregateDevice(status)
        }
        return deviceID
    }

    @available(macOS 14.2, *)
    private func readTapFormat(tapID: AudioObjectID) throws -> AVAudioFormat {
        var asbd = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, &asbd)
        guard status == noErr else {
            throw SystemAudioCaptureError.unableToReadTapFormat(status)
        }

        var mutableASBD = asbd
        guard
            asbd.mFormatID == kAudioFormatLinearPCM,
            let format = AVAudioFormat(streamDescription: &mutableASBD)
        else {
            throw SystemAudioCaptureError.invalidTapFormat
        }
        return format
    }

    @available(macOS 14.2, *)
    private func readTapUID(tapID: AudioObjectID) throws -> String {
        var tapUID: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, &tapUID)
        guard status == noErr else {
            throw SystemAudioCaptureError.unableToReadTapUID(status)
        }

        return tapUID as String
    }

    private func handleInputData(_ inputData: UnsafePointer<AudioBufferList>?) {
        guard
            let inputData,
            let sourceFormat,
            let converter,
            let bufferHandler
        else {
            return
        }

        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            bufferListNoCopy: inputData,
            deallocator: nil
        ) else {
            return
        }

        let sourceASBD = sourceFormat.streamDescription.pointee
        guard sourceASBD.mBytesPerFrame > 0 else {
            return
        }

        let firstBuffer = inputData.pointee.mBuffers
        let frameLength = AVAudioFrameCount(firstBuffer.mDataByteSize) / sourceASBD.mBytesPerFrame
        guard frameLength > 0 else {
            return
        }
        inputBuffer.frameLength = frameLength

        logger.debug("SystemAudioCapture input frameLength=\(frameLength)")
        let inputLevel = AudioLevelMeter.normalizedLevel(for: inputBuffer)
        logger.debug(
            "SystemAudioCapture input level=\(inputLevel, privacy: .public) format=\(sourceFormat.commonFormat.rawValue, privacy: .public) interleaved=\(sourceFormat.isInterleaved, privacy: .public) channels=\(sourceFormat.channelCount)"
        )

        let outputFrameCapacity = max(
            AVAudioFrameCount(frameLength),
            max(
                1,
                AVAudioFrameCount(
                    ceil(Double(frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate)
                )
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
            logger.error(
                "SystemAudioCapture convert failed status=\(String(describing: status), privacy: .public) error=\(conversionError?.localizedDescription ?? "unknown", privacy: .public)"
            )
            bufferHandler(inputBuffer)
            return
        }

        guard outputBuffer.frameLength > 0 else {
            logger.error("SystemAudioCapture produced empty converted buffer; falling back to input buffer for metering")
            bufferHandler(inputBuffer)
            return
        }

        let outputLevel = AudioLevelMeter.normalizedLevel(for: outputBuffer)
        logger.debug(
            "SystemAudioCapture output level=\(outputLevel, privacy: .public) frameLength=\(outputBuffer.frameLength)"
        )

        bufferHandler(outputBuffer)
    }

    private func cleanup() {
        tapID = nil
        aggregateDeviceID = nil
        ioProcID = nil
        converter = nil
        sourceFormat = nil
        bufferHandler = nil
        selectedProcesses = []
        isRunning = false
        isPaused = false
    }
}

extension SystemAudioCapture: SystemAudioCapturing {}
