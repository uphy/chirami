import Foundation
import Yams

class AppState: ObservableObject {
    static let shared = AppState()

    private let stateURL: URL
    @Published private(set) var state: FusenState = FusenState()

    private init() {
        let stateDir = FileManager.realHomeDirectory
            .appendingPathComponent(".local/state/fusen")
        stateURL = stateDir.appendingPathComponent("state.yaml")

        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let yaml = String(data: data, encoding: .utf8) else {
            state = FusenState()
            return
        }
        do {
            state = try YAMLDecoder().decode(FusenState.self, from: yaml)
        } catch {
            print("State load error: \(error)")
            state = FusenState()
        }
    }

    func save() {
        do {
            let yaml = try YAMLEncoder().encode(state)
            try yaml.write(to: stateURL, atomically: true, encoding: .utf8)
        } catch {
            print("State save error: \(error)")
        }
    }

    func windowState(for noteId: String) -> WindowState? {
        state.windows[noteId]
    }

    func updateWindow(for noteId: String, position: CGPoint, size: CGSize, visible: Bool) {
        state.windows[noteId] = WindowState(position: position, size: size, visible: visible)
        save()
    }

    func saveBookmark(for noteId: String, data: Data) {
        state.bookmarks[noteId] = data.base64EncodedString()
        save()
    }

    func bookmarkData(for noteId: String) -> Data? {
        guard let base64 = state.bookmarks[noteId] else { return nil }
        return Data(base64Encoded: base64)
    }

    func removeBookmark(for noteId: String) {
        state.bookmarks.removeValue(forKey: noteId)
        save()
    }

    func setAlwaysOnTop(_ value: Bool, for noteId: String) {
        if var ws = state.windows[noteId] {
            ws.alwaysOnTop = value
            state.windows[noteId] = ws
        } else {
            state.windows[noteId] = WindowState(
                position: CGPoint(x: 100, y: 200),
                size: CGSize(width: 300, height: 400),
                visible: true,
                alwaysOnTop: value
            )
        }
        save()
    }

    func setVisible(_ visible: Bool, for noteId: String) {
        if var ws = state.windows[noteId] {
            ws.visible = visible
            state.windows[noteId] = ws
        } else {
            state.windows[noteId] = WindowState(
                position: CGPoint(x: 100, y: 200),
                size: CGSize(width: 300, height: 400),
                visible: visible
            )
        }
        save()
    }
}
