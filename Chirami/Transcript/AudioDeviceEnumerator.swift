import AVFoundation
import CoreAudio
import Foundation

struct AudioDeviceDescriptor: Codable, Equatable, Sendable, Identifiable {
    var id: String { uniqueID }
    var uniqueID: String
    var name: String
}

enum AudioDeviceEnumerator {
    static func audioInputDevices() -> [AudioDeviceDescriptor] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
            .map { device in
                AudioDeviceDescriptor(
                    uniqueID: device.uniqueID,
                    name: device.localizedName
                )
            }
    }

    static func defaultAudioInputDevice() -> AudioDeviceDescriptor? {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            return nil
        }
        return AudioDeviceDescriptor(
            uniqueID: device.uniqueID,
            name: device.localizedName
        )
    }

    /// Resolves a device uniqueID (kAudioDevicePropertyDeviceUID) to its CoreAudio AudioDeviceID.
    static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(0)
        guard AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else {
            return nil
        }

        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(
            systemObjectID,
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return nil
        }

        return deviceIDs.first { readDeviceUID(deviceID: $0) == uid }
    }

    private static func readDeviceUID(deviceID: AudioDeviceID) -> String? {
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid) == noErr else {
            return nil
        }
        return uid as String
    }
}
