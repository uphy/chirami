import Foundation

class AppState: YAMLStore<ChiramiState> {
    static let shared = AppState()

    var state: ChiramiState { data }

    private static let defaultWindowState = WindowState(
        position: CGPoint(x: 100, y: 200),
        size: CGSize(width: 300, height: 400),
        visible: true
    )

    private init() {
        let stateDir = FileManager.realHomeDirectory
            .appendingPathComponent(".local/state/chirami")
        super.init(directory: stateDir, fileName: "state.yaml", label: "State", defaultValue: ChiramiState())
    }

    func windowState(for noteId: String) -> WindowState? {
        data.windows[noteId]
    }

    func updateWindow(for noteId: String, position: CGPoint, size: CGSize, visible: Bool) {
        updateWindowState(for: noteId) { ws in
            ws.position = [position.x, position.y]
            ws.size = [size.width, size.height]
            ws.visible = visible
        }
    }

    func saveBookmark(for noteId: String, data bookmarkData: Data) {
        update { $0.bookmarks[noteId] = bookmarkData.base64EncodedString() }
    }

    func bookmarkData(for noteId: String) -> Data? {
        guard let base64 = data.bookmarks[noteId] else { return nil }
        return Data(base64Encoded: base64)
    }

    func removeBookmark(for noteId: String) {
        update { $0.bookmarks.removeValue(forKey: noteId) }
    }

    func setPinned(_ value: Bool, for noteId: String) {
        updateWindowState(for: noteId) { $0.pinned = value }
    }

    func setAlwaysOnTop(_ value: Bool, for noteId: String) {
        updateWindowState(for: noteId) { $0.alwaysOnTop = value }
    }

    func setVisible(_ visible: Bool, for noteId: String) {
        updateWindowState(for: noteId) { $0.visible = visible }
    }

    func updateEditorState(for noteId: String, cursorPosition: Int, scrollOffset: CGPoint) {
        updateWindowState(for: noteId) { ws in
            ws.cursorPosition = cursorPosition
            ws.scrollOffset = [scrollOffset.x, scrollOffset.y]
        }
    }

    /// Remove oldest ad-hoc state entries if the count exceeds the limit.
    func pruneAdhocEntries(limit: Int = 100) {
        update { state in
            let adhocEntries = state.windows.filter { $0.key.hasPrefix("adhoc:") }
            guard adhocEntries.count > limit else { return }
            let sorted = adhocEntries.sorted { ($0.value.lastUsed ?? .distantPast) < ($1.value.lastUsed ?? .distantPast) }
            let toRemove = sorted.prefix(adhocEntries.count - limit)
            for (key, _) in toRemove {
                state.windows.removeValue(forKey: key)
            }
        }
    }

    private func updateWindowState(for noteId: String, _ modify: (inout WindowState) -> Void) {
        update { state in
            var ws = state.windows[noteId] ?? Self.defaultWindowState
            modify(&ws)
            state.windows[noteId] = ws
        }
    }
}
