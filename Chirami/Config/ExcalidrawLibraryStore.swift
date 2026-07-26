import Foundation
import os

/// Loads external Excalidraw library files specified in config.yaml and merges them with
/// user-saved items from PluginStateStore. Returns a combined payload for the JS side.
@MainActor
final class ExcalidrawLibraryStore {
    static let shared = ExcalidrawLibraryStore()
    static let pluginId = "excalidraw"
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "ExcalidrawLibraryStore")

    private init() {}

    private var libraryURLs: [URL] {
        (AppConfig.shared.config.excalidraw?.libraries ?? []).map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        }
    }

    /// Returns a JSON string of `{ "userItems": [...], "externalItems": [...] }`.
    /// `userItems` comes from PluginStateStore; `externalItems` is merged from all configured library files.
    /// Returns nil only on JSON serialization failure.
    func load() -> String? {
        let userItemsArray = loadUserItems()
        let externalItemsArray = loadExternalItems()

        let result: [String: Any] = [
            "userItems": userItemsArray,
            "externalItems": externalItemsArray
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: result),
              let json = String(data: data, encoding: .utf8) else {
            logger.error("Failed to serialize ExcalidrawLibraryStore payload")
            return nil
        }
        return json
    }

    // MARK: - Private

    private func loadUserItems() -> [[String: Any]] {
        guard let json = PluginStateStore.shared.load(pluginId: Self.pluginId),
              let data = json.data(using: .utf8) else { return [] }
        return parseLibraryItems(from: data, filename: "user") ?? []
    }

    private func loadExternalItems() -> [[String: Any]] {
        var result: [[String: Any]] = []
        for url in libraryURLs {
            guard let data = try? Data(contentsOf: url) else {
                logger.warning("External library file not found: \(url.path, privacy: .public)")
                continue
            }
            let filename = url.deletingPathExtension().lastPathComponent
            if let items = parseLibraryItems(from: data, filename: filename) {
                result.append(contentsOf: items)
                logger.debug("Loaded \(items.count, privacy: .public) items from \(url.lastPathComponent, privacy: .public)")
            } else {
                logger.warning("Failed to parse library file: \(url.lastPathComponent, privacy: .public)")
            }
        }
        return result
    }

    /// Parses a `.excalidrawlib` file (version 1 or 2) or a raw LibraryItems JSON array.
    /// Version 1: `library` is `[[ExcalidrawElement]]` — converted to LibraryItem format.
    /// Version 2: `library` is `[LibraryItem]` — used as-is.
    private func parseLibraryItems(from data: Data, filename: String) -> [[String: Any]]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        if let dict = json as? [String: Any], let library = dict["library"] {
            let version = dict["version"] as? Int ?? 2

            if version == 1, let v1Library = library as? [[[String: Any]]] {
                // Version 1: each entry is an [ExcalidrawElement] array — wrap into LibraryItem shape
                return v1Library.enumerated().map { index, elements in
                    ["id": "\(filename)-\(index)",
                     "status": "published",
                     "elements": elements,
                     "created": 0] as [String: Any]
                }
            }
            if let v2Library = library as? [[String: Any]] {
                return v2Library
            }
        }
        // Raw array format (legacy PluginStateStore format)
        if let array = json as? [[String: Any]] {
            return array
        }
        return nil
    }
}
