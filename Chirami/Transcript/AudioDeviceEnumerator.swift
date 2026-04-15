import AVFoundation
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
}
