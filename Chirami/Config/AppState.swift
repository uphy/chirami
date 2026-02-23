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
        update { $0.windows[noteId] = WindowState(position: position, size: size, visible: visible) }
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

    func setAlwaysOnTop(_ value: Bool, for noteId: String) {
        updateWindowState(for: noteId) { $0.alwaysOnTop = value }
    }

    func setVisible(_ visible: Bool, for noteId: String) {
        updateWindowState(for: noteId) { $0.visible = visible }
    }

    private func updateWindowState(for noteId: String, _ modify: (inout WindowState) -> Void) {
        update { state in
            var ws = state.windows[noteId] ?? Self.defaultWindowState
            modify(&ws)
            state.windows[noteId] = ws
        }
    }
}
