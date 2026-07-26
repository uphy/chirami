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
    private let appConfig: AppConfig
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var accessedURLs: [String: URL] = [:]

    /// Tests must pass tmpdir-based `AppConfig`/`AppState` instances so the
    /// real config/state directories are never touched.
    init(config: AppConfig = .shared, state: AppState = .shared) {
        self.appConfig = config
        self.appState = state
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

        notes = config.notes.compactMap { resolveNote(from: $0) }
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
        return makeTemplateNote(url: url, config: config, mode: .periodic)
    }

    /// Resolves a Note in stream mode: "current" is the lexicographically last
    /// file matching the template, or — when the directory has no matches yet —
    /// a newly created file from the template resolved at the current time
    /// (`*` → "", per `PathTemplateResolver.resolveStream`). Mirrors
    /// `resolvePeriodicNote`'s file-creation contract but resolves "current"
    /// from the directory listing instead of the current time.
    func resolveStreamNote(from config: NoteConfig) -> Note? {
        guard let url = latestOrNewStreamURL(for: config) else { return nil }
        return makeTemplateNote(url: url, config: config, mode: .stream)
    }

    /// Stream "create" hotkey (quick capture): always creates a brand-new file
    /// from the template resolved at the current time, regardless of whether a
    /// matching file already exists. Distinct from `resolveStreamNote`, which
    /// reuses the existing latest file when one is present.
    func createStreamEntry(from config: NoteConfig) -> Note? {
        let resolvedPath = PathTemplateResolver.resolveStream(config.path, for: Date())
        guard let url = resolvePath(resolvedPath) else { return nil }
        return makeTemplateNote(url: url, config: config, mode: .stream)
    }

    /// Returns the latest matching file for a stream template, or the
    /// current-time-resolved path when no matching file exists yet.
    private func latestOrNewStreamURL(for config: NoteConfig) -> URL? {
        let baseDir = PathTemplateResolver.extractBaseDirectory(from: config.path)
        guard let baseDirURL = resolvePath(baseDir) else { return nil }
        let relativeTemplate = String(config.path.dropFirst(baseDir.count))

        if let latest = PeriodicFileNavigator.latestMatchingFile(template: relativeTemplate, baseDirectory: baseDirURL) {
            return latest
        }

        let resolvedPath = PathTemplateResolver.resolveStream(config.path, for: Date())
        return resolvePath(resolvedPath)
    }

    /// Shared periodic/stream note construction: ensures the target file exists
    /// (copying from `config.template` if configured, else an empty file),
    /// builds title/appearance, and packages a `PeriodicNoteInfo` tagged with
    /// `mode` so window/navigation code can branch on periodic vs. stream.
    private func makeTemplateNote(url: URL, config: NoteConfig, mode: NoteMode) -> Note {
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

        let transparency = config.resolveTransparency()
        let alwaysOnTop = config.resolveAlwaysOnTop()
        let notePosition = config.resolvePosition()

        // rollover_delay has no meaning for stream notes (no time-based "current"
        // to roll over); ignore it at runtime regardless of what's configured.
        let rolloverDelay = mode == .stream ? 0 : DurationParser.parse(config.rolloverDelay)
        let templateFile: URL? = config.template.flatMap { resolvePath($0) }

        let periodicInfo = PeriodicNoteInfo(
            pathTemplate: config.path,
            rolloverDelay: rolloverDelay,
            templateFile: templateFile,
            titlePrefix: config.title,
            mode: mode
        )

        let attachmentsDir = config.resolveAttachmentsDir(
            noteURL: url,
            isPeriodicNote: true, pathTemplate: config.path
        )

        return Note(
            id: id, path: url, title: title, theme: config.theme,
            transparency: transparency,
            alwaysOnTop: alwaysOnTop, hotkeys: config.hotkeys,
            position: notePosition,
            periodicInfo: periodicInfo,
            attachmentsDir: attachmentsDir
        )
    }

    /// Returns the original NoteConfig from config.yaml for the given noteId.
    func noteConfig(for noteId: String) -> NoteConfig? {
        appConfig.config.notes.first { $0.noteId == noteId }
    }

    /// - Parameter isCreateAction: true when triggered by the `create` hotkey.
    ///   For static notes this ensures the file exists; for stream notes this
    ///   forces a brand-new quick-capture entry instead of reusing latest.
    func refreshNote(for noteId: String, isCreateAction: Bool = false) -> Note? {
        guard let config = noteConfig(for: noteId),
              let note = resolveNote(from: config, isCreateAction: isCreateAction) else {
            return nil
        }

        if let idx = notes.firstIndex(where: { $0.id == noteId }) {
            if notes[idx] != note { notes[idx] = note }
        } else {
            notes.append(note)
        }

        return note
    }

    private func resolveNote(from config: NoteConfig, isCreateAction: Bool = false) -> Note? {
        guard config.isConfigValid else {
            let errors = config.configErrors.map(\.description).joined(separator: "; ")
            logger.warning("skipping note with invalid config: path=\(config.path, privacy: .public) errors=\(errors, privacy: .public)")
            return nil
        }

        if config.isPeriodicNote {
            switch config.mode {
            case .stream:
                return isCreateAction ? createStreamEntry(from: config) : resolveStreamNote(from: config)
            case .periodic:
                let rolloverDelay = DurationParser.parse(config.rolloverDelay)
                let date = logicalDate(rolloverDelay: rolloverDelay)
                return resolvePeriodicNote(from: config, for: date)
            }
        }

        return resolveStaticNote(from: config, ensureFileExists: isCreateAction)
    }

    private func resolveStaticNote(from config: NoteConfig, ensureFileExists: Bool = false) -> Note? {
        guard let fallbackURL = resolvePath(config.path) else { return nil }

        let id = config.noteId
        let url = resolveBookmark(for: id) ?? fallbackURL
        if ensureFileExists {
            ensureFileExistsIfNeeded(at: url)
        }

        let title = config.title
            ?? URL(fileURLWithPath: config.resolvedPath)
                .deletingPathExtension().lastPathComponent
        let transparency = config.resolveTransparency()
        let alwaysOnTop = config.resolveAlwaysOnTop()
        let notePosition = config.resolvePosition()

        let attachmentsDir = config.resolveAttachmentsDir(
            noteURL: url,
            isPeriodicNote: false, pathTemplate: nil
        )

        return Note(
            id: id, path: url, title: title, theme: config.theme,
            transparency: transparency,
            alwaysOnTop: alwaysOnTop, hotkeys: config.hotkeys,
            position: notePosition,
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

    private func ensureFileExistsIfNeeded(at url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
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
