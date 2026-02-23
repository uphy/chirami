import SwiftUI
import Combine

@main
struct FusenApp: App {
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
        // Open all note windows
        windowManager.openAllWindows()

        // Register per-note hotkeys
        registerAllHotkeys()

        // Start Karabiner-Elements variable sync
        karabinerService.startObserving()

        // Re-register hotkeys when notes change (e.g., config reload)
        noteStore.$notes
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.registerAllHotkeys()
                    self?.windowManager.reloadWindows()
                }
            }
            .store(in: &cancellables)
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
