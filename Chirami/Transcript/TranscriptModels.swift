import Foundation

enum TranscriptStatus: String, Codable, Equatable {
    case idle = "Idle"
    case recording = "Recording"
    case paused = "Paused"
    case processing = "Processing"
    case completed = "Completed"
    case error = "Error"
}

enum TranscriptSource: String, Codable, Equatable {
    case mic
    case system
}

struct TranscriptBlockRange: Codable, Equatable {
    var blockFrom: Int
    var blockTo: Int
}

struct TranscriptChunk: Codable, Equatable {
    var source: TranscriptSource
    var timestamp: TimeInterval
    var text: String
}

struct TranscriptPreview: Codable, Equatable {
    var source: TranscriptSource
    var timestamp: TimeInterval
    var text: String
}

struct TranscriptChunkMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var source: TranscriptSource
    var timestamp: TimeInterval
    var text: String
}

struct TranscriptPreviewMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var source: TranscriptSource
    var timestamp: TimeInterval
    var text: String
}

struct TranscriptStateMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var status: TranscriptStatus
    var modelLabel: String
    var micDeviceLabel: String
    var systemDeviceLabel: String
}

struct TranscriptDeviceSnapshot: Codable, Equatable {
    var value: String
    var label: String
}

struct TranscriptRecordStartMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var micDevice: TranscriptDeviceSnapshot
    var systemDevice: TranscriptDeviceSnapshot
}

struct TranscriptDevicesRequestMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var source: TranscriptSource
}

struct TranscriptLevelUpdateMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var source: TranscriptSource
    var level: Double
}

struct TranscriptDeviceOptionMessage: Codable, Equatable {
    var value: String
    var label: String
    var detail: String?
    var active: Bool?
}

struct TranscriptDevicesListMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var source: TranscriptSource
    var devices: [TranscriptDeviceOptionMessage]
    var selectedValue: String?
}

struct TranscriptModelDownloadProgressMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var modelLabel: String
    var progress: TranscriptDownloadProgress
}

struct TranscriptDownloadProgress: Codable, Equatable {
    var fractionCompleted: Double
    var receivedBytes: Int
    var totalBytes: Int
}

struct TranscriptErrorMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var message: String
}

struct TranscriptDeviceSelectionMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var source: TranscriptSource
    var value: String
}

struct TranscriptLineFormatter {
    var labels: TranscriptLabelConfig

    init(labels: TranscriptLabelConfig = TranscriptLabelConfig()) {
        self.labels = labels
    }

    func format(_ chunk: TranscriptChunk) -> String {
        let minute = max(0, Int(chunk.timestamp)) / 60
        let second = max(0, Int(chunk.timestamp)) % 60
        let label = label(for: chunk.source)
        let text = normalize(chunk.text)
        return String(format: "[%02d:%02d] %@: %@", minute, second, label, text)
    }

    private func label(for source: TranscriptSource) -> String {
        switch source {
        case .mic:
            return labels.mic
        case .system:
            return labels.system
        }
    }

    private func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
