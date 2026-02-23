import AppKit
import Foundation

/// Monitors NotePanel focus state and sets Karabiner-Elements variables via karabiner_cli.
@MainActor
class KarabinerService {
    static let shared = KarabinerService()

    private static let cliPath = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"

    private var focusedPanelCount = 0
    private var lastSetValue: KarabinerValue?
    private var pendingUnfocusWorkItem: DispatchWorkItem?
    private var becomeKeyObserver: NSObjectProtocol?
    private var resignKeyObserver: NSObjectProtocol?

    private init() {}

    func startObserving() {
        becomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard notification.object is NotePanel else { return }
            Task { @MainActor in
                self?.handleWindowFocus()
            }
        }

        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard notification.object is NotePanel else { return }
            Task { @MainActor in
                self?.handleWindowUnfocus()
            }
        }
    }

    func stopObserving() {
        if let observer = becomeKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            becomeKeyObserver = nil
        }
        if let observer = resignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            resignKeyObserver = nil
        }
        pendingUnfocusWorkItem?.cancel()
        pendingUnfocusWorkItem = nil
    }

    // MARK: - Focus handling

    private func handleWindowFocus() {
        pendingUnfocusWorkItem?.cancel()
        pendingUnfocusWorkItem = nil

        focusedPanelCount += 1

        if focusedPanelCount == 1 {
            guard let config = AppConfig.shared.config.karabiner else { return }
            setVariable(name: config.variable, value: config.onFocus)
        }
    }

    private func handleWindowUnfocus() {
        focusedPanelCount = max(0, focusedPanelCount - 1)

        if focusedPanelCount == 0 {
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self, self.focusedPanelCount == 0 else { return }
                    guard let config = AppConfig.shared.config.karabiner else { return }
                    self.setVariable(name: config.variable, value: config.onUnfocus)
                }
            }
            pendingUnfocusWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }
    }

    // MARK: - CLI execution

    private func setVariable(name: String, value: KarabinerValue) {
        if lastSetValue == value { return }
        lastSetValue = value

        let cliPath = AppConfig.shared.config.karabiner?.cliPath ?? Self.cliPath
        let jsonFragment = value.jsonFragment
        Task.detached {
            guard FileManager.default.fileExists(atPath: cliPath) else {
                print("KarabinerService: karabiner_cli not found at \(cliPath)")
                return
            }

            let json = "{\"\(name)\": \(jsonFragment)}"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cliPath)
            process.arguments = ["--set-variables", json]

            let errorPipe = Pipe()
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus != 0 {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? ""
                    print("KarabinerService: karabiner_cli failed (exit \(process.terminationStatus)): \(errorMessage)")
                }
            } catch {
                print("KarabinerService: failed to launch karabiner_cli: \(error)")
            }
        }
    }
}
