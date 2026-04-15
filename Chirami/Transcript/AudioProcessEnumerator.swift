import CoreAudio
import Foundation
import AppKit

struct AudioProcessDescriptor: Codable, Equatable, Sendable, Identifiable {
    var id: pid_t { pid }
    var objectID: AudioObjectID
    var pid: pid_t
    var bundleID: String?
    var applicationName: String?
    var isRunningInput: Bool
    var isRunningOutput: Bool

    var displayLabel: String {
        if let applicationName, !applicationName.isEmpty {
            return applicationName
        }
        if let bundleID, !bundleID.isEmpty {
            return bundleID
        }
        return "PID \(pid)"
    }

    var transcriptValue: String {
        return "pid:\(pid)"
    }

    var transcriptDetail: String {
        if let bundleID, !bundleID.isEmpty {
            return "\(bundleID) · PID \(pid)"
        }
        return "PID \(pid)"
    }
}

enum AudioProcessEnumerator {
    static func runningOutputProcesses() -> [AudioProcessDescriptor] {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(0)
        guard AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else {
            return []
        }

        var processObjectIDs = Array(repeating: AudioObjectID(), count: count)
        guard AudioObjectGetPropertyData(
            systemObjectID,
            &address,
            0,
            nil,
            &dataSize,
            &processObjectIDs
        ) == noErr else {
            return []
        }

        return processObjectIDs
            .compactMap { loadProcessDescriptor(objectID: $0) }
            .filter { $0.isRunningOutput }
    }

    static func runningInputProcesses() -> [AudioProcessDescriptor] {
        runningOutputProcesses().filter { $0.isRunningInput }
    }

    private static func loadProcessDescriptor(objectID: AudioObjectID) -> AudioProcessDescriptor? {
        guard let pid = readProcessID(objectID: objectID) else {
            return nil
        }

        let bundleID = readProcessBundleID(objectID: objectID)
        let applicationName = NSRunningApplication(processIdentifier: pid)?.localizedName
        let isRunningInput = readProcessState(objectID: objectID, selector: kAudioProcessPropertyIsRunningInput)
        let isRunningOutput = readProcessState(objectID: objectID, selector: kAudioProcessPropertyIsRunningOutput)

        return AudioProcessDescriptor(
            objectID: objectID,
            pid: pid,
            bundleID: bundleID,
            applicationName: applicationName,
            isRunningInput: isRunningInput,
            isRunningOutput: isRunningOutput
        )
    }

    private static func readProcessID(objectID: AudioObjectID) -> pid_t? {
        var value = pid_t(0)
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func readProcessBundleID(objectID: AudioObjectID) -> String? {
        var bundleID: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &bundleID) == noErr else {
            return nil
        }
        return bundleID as String
    }

    private static func readProcessState(objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> Bool {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }
}
