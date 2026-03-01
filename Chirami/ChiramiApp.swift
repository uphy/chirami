import SwiftUI
import Combine

@main
struct ChiramiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            NoteListView()
        } label: {
            Image(systemName: "note.text")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager = WindowManager.shared
    private let noteStore = NoteStore.shared
    private let hotkeyService = GlobalHotkeyService()
    private let karabinerService = KarabinerService.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply appearance mode from config
        applyAppearance()

        // Open all note windows
        windowManager.openAllWindows()

        // Register per-note hotkeys
        registerAllHotkeys()

        // Start Karabiner-Elements variable sync
        karabinerService.startObserving()

        // Clean up orphaned attachment images in the background
        let notesSnapshot = noteStore.notes
        Task.detached {
            AttachmentCleanupService.cleanupOrphanedAttachments(notes: notesSnapshot)
        }

        // Re-register hotkeys when notes change (e.g., config reload)
        noteStore.$notes
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyAppearance()
                    self?.registerAllHotkeys()
                    self?.windowManager.reloadWindows()
                }
            }
            .store(in: &cancellables)
    }

    func applyAppearance() {
        switch AppConfig.shared.config.resolvedAppearanceMode {
        case .auto:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func registerAllHotkeys() {
        hotkeyService.unregisterAll()
        if let globalKey = AppConfig.shared.config.hotkey {
            hotkeyService.register(id: "global:toggleAll", keyString: globalKey) { [weak self] in
                Task { @MainActor in
                    self?.windowManager.toggleAllWindows()
                }
            }
        }
        for note in noteStore.notes {
            guard let keyString = note.hotkey else { continue }
            let noteId = note.id
            hotkeyService.register(id: "note:\(noteId)", keyString: keyString) { [weak self] in
                Task { @MainActor in
                    self?.windowManager.toggleWindow(for: noteId)
                }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSLog("[AppDelegate] application(_:open:) called with %d URL(s)", urls.count)
        for url in urls {
            NSLog("[AppDelegate] URL: %@", url.absoluteString)
            guard url.scheme == "chirami" else { continue }
            if url.host == "display" {
                DisplayWindowManager.shared.display(url: url)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        noteStore.stopAccessingAllResources()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowManager.showAllWindows()
        }
        return true
    }
}
