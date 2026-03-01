import AppKit
import SwiftUI

/// Manages windows for Registered Notes: creation, show/hide, always-on-top, transparency.
@MainActor
class WindowManager: ObservableObject {
    static let shared = WindowManager()

    private var controllers: [String: NoteWindowController] = [:]
    private let noteStore = NoteStore.shared
    private var rolloverTimer: Timer?

    private init() {}

    func openAllWindows() {
        var cascadePoint = CGPoint.zero
        for note in noteStore.notes {
            let hasSavedState = noteStore.windowState(for: note) != nil
            openWindow(for: note)
            if !hasSavedState, let window = controllers[note.id]?.window {
                cascadePoint = window.cascadeTopLeft(from: cascadePoint)
            }
        }
    }

    func openWindow(for note: Note) {
        if let existing = controllers[note.id] {
            existing.showWindow(nil)
            return
        }

        let controller = NoteWindowController(note: note)
        controllers[note.id] = controller

        let pinned = noteStore.isPinned(note)

        // Unpinned cursor notes start hidden
        if !pinned && note.position == .cursor {
            return
        }

        if pinned {
            // Pinned notes always show on launch
            controller.show()
        } else {
            controller.showIfNeeded()
        }
    }

    func toggleAllWindows() {
        let pinnedControllers = controllers.values.filter { noteStore.isPinned($0.note) }
        let anyVisible = pinnedControllers.contains { $0.isVisible }
        if anyVisible {
            hideAllWindows()
        } else {
            showAllWindows()
        }
    }

    func showAllWindows() {
        for note in noteStore.notes where noteStore.isPinned(note) {
            openWindow(for: note)
            controllers[note.id]?.show()
        }
    }

    func hideAllWindows() {
        controllers.values.filter { noteStore.isPinned($0.note) }.forEach { $0.hide() }
    }

    func toggleWindow(for noteId: String) {
        guard let controller = controllers[noteId] else {
            if let note = noteStore.notes.first(where: { $0.id == noteId }) {
                openWindow(for: note)
            }
            return
        }
        controller.toggle()
    }

    func isVisible(noteId: String) -> Bool {
        controllers[noteId]?.isVisible ?? false
    }

    func reloadWindows() {
        // Close windows for removed notes
        let currentIds = Set(noteStore.notes.map { $0.id })
        for id in controllers.keys where !currentIds.contains(id) {
            controllers[id]?.close()
            controllers.removeValue(forKey: id)
        }
        // Open new notes
        for note in noteStore.notes where controllers[note.id] == nil {
            openWindow(for: note)
        }

        // Manage rollover timer
        let hasPeriodicNotes = noteStore.notes.contains { $0.periodicInfo != nil }
        if hasPeriodicNotes {
            startRolloverTimer()
        } else {
            stopRolloverTimer()
        }
    }

    // MARK: - Rollover

    func startRolloverTimer() {
        guard rolloverTimer == nil else { return }
        rolloverTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkRollover()
            }
        }
    }

    func stopRolloverTimer() {
        rolloverTimer?.invalidate()
        rolloverTimer = nil
    }

    func checkRollover() {
        for (_, controller) in controllers {
            guard let info = controller.note.periodicInfo else { continue }
            let logicalDate = noteStore.logicalDate(rolloverDelay: info.rolloverDelay)
            let newPath = PathTemplateResolver.resolve(info.pathTemplate, for: logicalDate)
            guard let newURL = resolvePath(newPath) else { continue }

            if newURL.path != controller.note.path.path {
                let config = NoteConfig(
                    path: info.pathTemplate,
                    title: info.titlePrefix,
                    template: info.templateFile?.path
                )
                if let newNote = noteStore.resolvePeriodicNote(from: config, for: logicalDate) {
                    controller.handleRollover(newNote)
                }
            }
        }
    }

    private func resolvePath(_ path: String) -> URL? {
        if path.hasPrefix("~/") {
            return FileManager.realHomeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }
}
