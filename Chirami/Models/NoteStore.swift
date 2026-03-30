import Foundation
import Combine
import os

/// Manages Registered Notes — notes defined in config.yaml's `notes[]` array.
/// Loads Static Notes and Periodic Notes from config, handles file I/O, and persists window state.
@MainActor
class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published private(set) var notes: [Note] = []

    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "NoteStore")
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

        if let userColorSchemes = config.colorSchemes {
            ColorSchemeRegistry.shared.loadUserColorSchemes(userColorSchemes)
        }

        notes = config.notes.compactMap { noteConfig in
            if noteConfig.isPeriodicNote {
                let rolloverDelay = DurationParser.parse(noteConfig.rolloverDelay)
                let date = logicalDate(rolloverDelay: rolloverDelay)
                return resolvePeriodicNote(from: noteConfig, for: date)
            }

            // Static Note: fixed file path
            guard let fallbackURL = resolvePath(noteConfig.path) else { return nil }

            let id = noteConfig.noteId
            let url = resolveBookmark(for: id) ?? fallbackURL
            let title = noteConfig.title
                ?? URL(fileURLWithPath: noteConfig.resolvedPath)
                    .deletingPathExtension().lastPathComponent
            let color = noteConfig.resolveNoteColorScheme()
            let transparency = noteConfig.resolveTransparency()
            let fontSize = noteConfig.resolveFontSize()

            let alwaysOnTop = noteConfig.resolveAlwaysOnTop()

            let notePosition = noteConfig.resolvePosition()

            let attachmentsDir = noteConfig.resolveAttachmentsDir(
                noteURL: url,
                isPeriodicNote: false, pathTemplate: nil
            )

            return Note(
                id: id, path: url, title: title, colorScheme: color,
                transparency: transparency, fontSize: fontSize,
                alwaysOnTop: alwaysOnTop, hotkey: noteConfig.hotkey,
                position: notePosition,
                attachmentsDir: attachmentsDir
            )
        }
    }

    // MARK: - Periodic Note

    /// Returns the logical date/time (current time minus rolloverDelay).
    func logicalDate(rolloverDelay: TimeInterval) -> Date {
        Date().addingTimeInterval(-rolloverDelay)
    }

    /// Resolves a Note for the given date from NoteConfig.
    /// Creates the file automatically if it does not exist (with template → copy template, without → empty file).
    func resolvePeriodicNote(from config: NoteConfig, for date: Date) -> Note? {
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
                    logger.warning("template file not found: \(config.template!, privacy: .public)")
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

        let color = config.resolveNoteColorScheme()
        let transparency = config.resolveTransparency()
        let fontSize = config.resolveFontSize()
        let alwaysOnTop = config.resolveAlwaysOnTop()
        let notePosition = config.resolvePosition()

        let rolloverDelay = DurationParser.parse(config.rolloverDelay)
        let templateFile: URL? = config.template.flatMap { resolvePath($0) }

        let periodicInfo = PeriodicNoteInfo(
            pathTemplate: config.path,
            rolloverDelay: rolloverDelay,
            templateFile: templateFile,
            titlePrefix: config.title
        )

        let attachmentsDir = config.resolveAttachmentsDir(
            noteURL: url,
            isPeriodicNote: true, pathTemplate: config.path
        )

        return Note(
            id: id, path: url, title: title, colorScheme: color,
            transparency: transparency, fontSize: fontSize,
            alwaysOnTop: alwaysOnTop, hotkey: config.hotkey,
            position: notePosition,
            periodicInfo: periodicInfo,
            attachmentsDir: attachmentsDir
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

    func updateNoteColorScheme(_ colorScheme: NoteColorScheme, for note: Note) {
        appConfig.update { config in
            if let idx = config.notes.firstIndex(where: { $0.noteId == note.id }) {
                config.notes[idx].colorScheme = colorScheme.rawValue
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

    func isPinned(_ note: Note) -> Bool {
        if let pinned = appState.windowState(for: note.id)?.pinned {
            return pinned
        }
        // Default: cursor notes are unpinned, fixed notes are pinned
        return note.position != .cursor
    }

    func setPinned(_ value: Bool, for note: Note) {
        appState.setPinned(value, for: note.id)
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
