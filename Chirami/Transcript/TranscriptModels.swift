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

struct TranscriptModelStateMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var modelLabel: String
    var selectedValue: String
    var models: [TranscriptDeviceOptionMessage]
    var metadata: TranscriptModelMetadataMessage?
}

struct TranscriptModelMetadataMessage: Codable, Equatable {
    var detail: String?
    var kindLabel: String?
    var configuredLanguage: String?
    var supportedLanguages: [String]?
    var installed: Bool?
    var installedSizeBytes: Int64?
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

struct TranscriptLevelMonitorStartMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var micDevice: TranscriptDeviceSnapshot
    var systemDevice: TranscriptDeviceSnapshot
}

struct TranscriptDevicesRequestMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var source: TranscriptSource
}

struct TranscriptModelRequestMessage: Codable, Equatable {
    var range: TranscriptBlockRange
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

enum TranscriptDownloadStage: String, Codable, Equatable {
    case downloading = "Downloading"
    case installing = "Installing"
    case preparing = "Preparing"
}

struct TranscriptDownloadProgress: Codable, Equatable {
    var fractionCompleted: Double
    var receivedBytes: Int
    var totalBytes: Int
    var stage: TranscriptDownloadStage
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

struct TranscriptModelSelectionMessage: Codable, Equatable {
    var range: TranscriptBlockRange
    var value: String
}

struct TranscriptLineFormatter {
    var labels: TranscriptLabelConfig
    var timeZone: TimeZone

    init(
        labels: TranscriptLabelConfig = TranscriptLabelConfig(),
        timeZone: TimeZone = .current
    ) {
        self.labels = labels
        self.timeZone = timeZone
    }

    func format(_ chunk: TranscriptChunk) -> String {
        let date = Date(timeIntervalSince1970: max(0, chunk.timestamp))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let label = label(for: chunk.source)
        let text = normalize(chunk.text)
        return String(
            format: "[%04d-%02d-%02d %02d:%02d:%02d] %@: %@",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            label,
            text
        )
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
