import Foundation

/// Stores per-plugin state as JSON files under ~/.local/state/chirami/plugins/{pluginId}.json.
/// Plugins use the bridge messages pluginStateRequest / pluginStateChanged to read and write state.
@MainActor
final class PluginStateStore {
    static let shared = PluginStateStore()
    private let directory: URL

    private init() {
        directory = FileManager.realHomeDirectory
            .appendingPathComponent(".local/state/chirami/plugins")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load(pluginId: String) -> String? {
        let fileURL = directory.appendingPathComponent("\(pluginId).json")
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    func save(pluginId: String, json: String) {
        let fileURL = directory.appendingPathComponent("\(pluginId).json")
        try? json.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
