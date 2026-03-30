import ServiceManagement
import SwiftUI
import Combine
import os

@main
struct ChiramiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appConfig = AppConfig.shared

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { appConfig.config.showMenuBarIcon ?? true },
            set: { _ in }
        )) {
            NoteListView()
        } label: {
            Image(nsImage: {
                let img = Bundle.main.image(forResource: "MenuBarIcon")
                    ?? NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)!
                img.isTemplate = true
                return img
            }())
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "AppDelegate")
    private let windowManager = WindowManager.shared
    private let noteStore = NoteStore.shared
    private let hotkeyService = GlobalHotkeyService()
    private let karabinerService = KarabinerService.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply appearance mode from config
        applyAppearance()

        // Apply launch-at-login from config
        applyLaunchAtLogin()

        // Prune stale Ad-hoc Note state entries
        AppState.shared.pruneAdhocEntries()

        // Open all Registered Note windows
        windowManager.openAllWindows()

        // Register per-note hotkeys
        registerAllHotkeys()

        // Start Karabiner-Elements variable sync
        karabinerService.startObserving()

        // Enable key focus after startup completes.
        DispatchQueue.main.async {
            NotePanel.startupMode = false
        }

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

        // Re-apply all config-driven settings when config changes
        AppConfig.shared.$data
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyAppearance()
                    self?.registerAllHotkeys()
                    self?.applyLaunchAtLogin()
                }
            }
            .store(in: &cancellables)
    }

    func applyLaunchAtLogin() {
        let enabled = AppConfig.shared.config.launchAtLogin ?? false
        let currentlyEnabled = SMAppService.mainApp.status == .enabled
        guard enabled != currentlyEnabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to \(enabled ? "register" : "unregister") login item: \(error, privacy: .public)")
        }
    }

    func applyAppearance() {
        switch AppConfig.shared.config.appearance ?? .auto {
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
        // Register profile hotkeys for Ad-hoc Notes
        if let profiles = AppConfig.shared.config.adhoc?.profiles {
            for (name, profile) in profiles {
                guard let keyString = profile.hotkey else { continue }
                let profileName = name
                hotkeyService.register(id: "adhoc-profile:\(profileName)", keyString: keyString) {
                    Task { @MainActor in
                        DisplayWindowManager.shared.toggleProfile(profileName)
                    }
                }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        logger.debug("application(_:open:) called with \(urls.count, privacy: .public) URL(s)")
        for url in urls {
            logger.debug("URL: \(url.absoluteString, privacy: .public)")
            guard url.scheme == "chirami" else { continue }
            if url.host == "display" {
                // Ad-hoc Note: opened dynamically via chirami://display URI
                DisplayWindowManager.shared.display(url: url)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowManager.saveAllEditorStates()
        noteStore.stopAccessingAllResources()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowManager.showAllWindows()
        }
        return true
    }
}
