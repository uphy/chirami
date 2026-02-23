import AppKit
import SwiftUI

/// Manages all note windows: creation, show/hide, always-on-top, transparency.
@MainActor
class WindowManager: ObservableObject {
    static let shared = WindowManager()

    private var controllers: [String: NoteWindowController] = [:]
    private let noteStore = NoteStore.shared

    private init() {}

    func openAllWindows() {
        for note in noteStore.notes {
            openWindow(for: note)
        }
    }

    func openWindow(for note: Note) {
        if let existing = controllers[note.id] {
            existing.showWindow(nil)
            return
        }

        let controller = NoteWindowController(note: note)
        controllers[note.id] = controller

        // Transient notes (auto_hide + cursor) start hidden
        if note.autoHide && note.position == .cursor {
            return
        }
        controller.showIfNeeded()
    }

    func toggleAllWindows() {
        let nonAutoHide = controllers.values.filter { !$0.note.autoHide }
        let anyVisible = nonAutoHide.contains { $0.isVisible }
        if anyVisible {
            if NSApp.isActive {
                hideAllWindows()
            } else {
                focusAllWindows()
            }
        } else {
            showAllWindows()
        }
    }

    func focusAllWindows() {
        NSApp.activate(ignoringOtherApps: true)
        var lastWindow: NSWindow?
        for (_, controller) in controllers where controller.isVisible && !controller.note.autoHide {
            controller.window?.orderFront(nil)
            lastWindow = controller.window
        }
        lastWindow?.makeKeyAndOrderFront(nil)
    }

    func showAllWindows() {
        for note in noteStore.notes where !note.autoHide {
            openWindow(for: note)
            controllers[note.id]?.show()
        }
    }

    func hideAllWindows() {
        controllers.values.filter { !$0.note.autoHide }.forEach { $0.hide() }
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
    }
}
