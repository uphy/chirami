import Foundation
import Combine

@MainActor
class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published private(set) var notes: [Note] = []

    private let appConfig = AppConfig.shared
    private let appState = AppState.shared
    private var cancellables = Set<AnyCancellable>()
    private var accessedURLs: [String: URL] = [:]

    private init() {
        loadFromConfig()

        // Reload when config changes externally
        appConfig.$data
            .dropFirst()
            .sink { [weak self] _ in self?.loadFromConfig() }
            .store(in: &cancellables)
    }

    func loadFromConfig() {
        stopAccessingAllResources()

        let config = appConfig.config

        notes = config.notes.compactMap { noteConfig in
            guard let fallbackURL = resolvePath(noteConfig.path) else { return nil }

            let id = noteConfig.noteId
            let url = resolveBookmark(for: id) ?? fallbackURL
            let title = noteConfig.title
                ?? URL(fileURLWithPath: noteConfig.resolvedPath)
                    .deletingPathExtension().lastPathComponent
            let color = noteConfig.color.flatMap { NoteColor(rawValue: $0) } ?? .yellow

            let transparency = noteConfig.transparency ?? 0.9
            let fontSize = CGFloat(noteConfig.fontSize ?? 14)

            let alwaysOnTop = appState.windowState(for: id)?.alwaysOnTop ?? true

            return Note(id: id, path: url, title: title, color: color, transparency: transparency, fontSize: fontSize, alwaysOnTop: alwaysOnTop, hotkey: noteConfig.hotkey)
        }
    }

    private func resolvePath(_ path: String) -> URL? {
        if path.hasPrefix("~/") {
            let expanded = FileManager.realHomeDirectory
                .appendingPathComponent(String(path.dropFirst(2)))
            return expanded
        }
        return URL(fileURLWithPath: path)
    }

    func readContent(of note: Note) -> String {
        (try? String(contentsOf: note.path, encoding: .utf8)) ?? ""
    }

    func writeContent(_ content: String, to note: Note) {
        // Create parent directories if needed
        let dir = note.path.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: note.path, atomically: true, encoding: .utf8)
    }

    func windowState(for note: Note) -> WindowState? {
        appState.windowState(for: note.id)
    }

    func saveWindowState(for note: Note, position: CGPoint, size: CGSize, visible: Bool) {
        appState.updateWindow(for: note.id, position: position, size: size, visible: visible)
    }

    func setVisible(_ visible: Bool, for note: Note) {
        appState.setVisible(visible, for: note.id)
    }

    func isVisible(_ note: Note) -> Bool {
        appState.windowState(for: note.id)?.visible ?? true
    }

    func updateColor(_ color: NoteColor, for note: Note) {
        appConfig.update { config in
            if let idx = config.notes.firstIndex(where: { $0.noteId == note.id }) {
                config.notes[idx].color = color.rawValue
            }
        }
        loadFromConfig()
    }

    func updateTransparency(_ value: Double, for note: Note) {
        appConfig.update { config in
            if let idx = config.notes.firstIndex(where: { $0.noteId == note.id }) {
                config.notes[idx].transparency = value
            }
        }
        loadFromConfig()
    }

    func updateAlwaysOnTop(_ value: Bool, for note: Note) {
        appState.setAlwaysOnTop(value, for: note.id)
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx].alwaysOnTop = value
        }
    }

    func addNote(path: URL, title: String? = nil, color: NoteColor = .yellow) {
        let home = FileManager.realHomeDirectory.path
        let pathStr = path.path.hasPrefix(home)
            ? "~/" + path.path.dropFirst(home.count + 1)
            : path.path

        let noteConfig = NoteConfig(
            path: pathStr,
            title: title,
            color: color.rawValue
        )
        appConfig.update { $0.notes.append(noteConfig) }
        loadFromConfig()
    }

    // MARK: - Security-Scoped Bookmarks

    func saveBookmark(for noteId: String, url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        appState.saveBookmark(for: noteId, data: data)
    }

    private func resolveBookmark(for noteId: String) -> URL? {
        guard let data = appState.bookmarkData(for: noteId) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            saveBookmark(for: noteId, url: url)
        }

        if url.startAccessingSecurityScopedResource() {
            accessedURLs[noteId] = url
        }
        return url
    }

    func stopAccessingAllResources() {
        for (_, url) in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()
    }
}
