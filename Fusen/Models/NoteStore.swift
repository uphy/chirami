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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadFromConfig() }
            .store(in: &cancellables)
    }

    func loadFromConfig() {
        stopAccessingAllResources()

        let config = appConfig.config

        notes = config.notes.compactMap { noteConfig in
            if noteConfig.isPeriodicNote {
                let rolloverDelay = DurationParser.parse(noteConfig.rolloverDelay)
                let date = logicalDate(rolloverDelay: rolloverDelay)
                return resolvePeriodicNote(from: noteConfig, for: date, defaults: config.defaults)
            }

            // Static note (existing logic)
            guard let fallbackURL = resolvePath(noteConfig.path) else { return nil }

            let id = noteConfig.noteId
            let url = resolveBookmark(for: id) ?? fallbackURL
            let title = noteConfig.title
                ?? URL(fileURLWithPath: noteConfig.resolvedPath)
                    .deletingPathExtension().lastPathComponent
            let color = noteConfig.resolveColor(defaults: config.defaults)
            let transparency = noteConfig.resolveTransparency(defaults: config.defaults)
            let fontSize = noteConfig.resolveFontSize(defaults: config.defaults)

            let alwaysOnTop = appState.windowState(for: id)?.alwaysOnTop ?? true

            let notePosition = noteConfig.resolvePosition(defaults: config.defaults)
            let autoHide = noteConfig.resolveAutoHide(defaults: config.defaults)

            return Note(
                id: id, path: url, title: title, color: color,
                transparency: transparency, fontSize: fontSize,
                alwaysOnTop: alwaysOnTop, hotkey: noteConfig.hotkey,
                position: notePosition, autoHide: autoHide
            )
        }
    }

    // MARK: - Periodic Note

    /// 論理日時を計算する（現在日時 − rolloverDelay）
    func logicalDate(rolloverDelay: TimeInterval) -> Date {
        Date().addingTimeInterval(-rolloverDelay)
    }

    /// NoteConfig から指定日付の Note を解決する
    /// ファイルが存在しない場合は自動作成する（template 指定あり → テンプレートコピー、なし → 空ファイル）
    func resolvePeriodicNote(from config: NoteConfig, for date: Date, defaults: NoteDefaults? = nil) -> Note? {
        let resolvedPath = PathTemplateResolver.resolve(config.path, for: date)
        guard let url = resolvePath(resolvedPath) else { return nil }

        let id = config.noteId

        // Create parent directory if needed
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: url.path) {
            if let templatePath = config.template,
               let templateURL = resolvePath(templatePath),
               FileManager.default.fileExists(atPath: templateURL.path) {
                try? FileManager.default.copyItem(at: templateURL, to: url)
            } else {
                if config.template != nil {
                    print("[Fusen] Warning: template file not found: \(config.template!)")
                }
                try? "".write(to: url, atomically: true, encoding: .utf8)
            }
        }

        // Title: "configTitle — resolvedFileName" or just the filename
        let fileName = url.deletingPathExtension().lastPathComponent
        let title: String
        if let configTitle = config.title {
            title = "\(configTitle) — \(fileName)"
        } else {
            title = fileName
        }

        let configDefaults = defaults ?? appConfig.config.defaults
        let color = config.resolveColor(defaults: configDefaults)
        let transparency = config.resolveTransparency(defaults: configDefaults)
        let fontSize = config.resolveFontSize(defaults: configDefaults)
        let alwaysOnTop = appState.windowState(for: id)?.alwaysOnTop ?? true
        let notePosition = config.resolvePosition(defaults: configDefaults)
        let autoHide = config.resolveAutoHide(defaults: configDefaults)

        let rolloverDelay = DurationParser.parse(config.rolloverDelay)
        let templateFile: URL? = config.template.flatMap { resolvePath($0) }

        let periodicInfo = PeriodicNoteInfo(
            pathTemplate: config.path,
            rolloverDelay: rolloverDelay,
            templateFile: templateFile,
            titlePrefix: config.title
        )

        return Note(
            id: id, path: url, title: title, color: color,
            transparency: transparency, fontSize: fontSize,
            alwaysOnTop: alwaysOnTop, hotkey: config.hotkey,
            position: notePosition, autoHide: autoHide,
            periodicInfo: periodicInfo
        )
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
