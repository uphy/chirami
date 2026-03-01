import AppKit

// MARK: - DisplayWindowController

/// Manages a single display window opened via chirami://display URI.
@MainActor
class DisplayWindowController: NSObject, NSWindowDelegate {

    let panel: DisplayPanel

    init(panel: DisplayPanel) {
        self.panel = panel
        super.init()
        panel.delegate = self
    }

    /// Center the panel on the main screen and show it.
    func show() {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = panel.frame.size
            let x = screenFrame.midX - windowSize.width / 2
            let y = screenFrame.midY - windowSize.height / 2
            panel.setFrameOrigin(CGPoint(x: x, y: y))
        }
        panel.orderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        DisplayWindowManager.shared.removeController(self)
    }
}

// MARK: - DisplayWindowManager

/// Manages all display windows opened via chirami://display URIs.
/// Parses URL parameters and creates/destroys DisplayWindowController instances.
@MainActor
class DisplayWindowManager {

    static let shared = DisplayWindowManager()

    private var controllers: [ObjectIdentifier: DisplayWindowController] = [:]

    private init() {}

    /// Parse a chirami://display URL and open a floating window.
    func display(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let queryItems = components.queryItems ?? []

        func param(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        let filePath = param("file")
        let content = param("content")
        let isReadOnly = param("readonly") == "1"
        let callbackPipePath = param("callback_pipe")

        // Validate callback_pipe: only allow paths under /tmp/ or $TMPDIR
        let validPipe: String? = callbackPipePath.flatMap { isValidCallbackPipe($0) ? $0 : nil }

        // Determine display content and file URL
        let displayContent: String
        let fileURL: URL?
        let readOnly: Bool

        if let filePath = filePath {
            let fileURLCandidate = URL(fileURLWithPath: filePath)
            if isReadOnly {
                displayContent = (try? String(contentsOf: fileURLCandidate, encoding: .utf8)) ?? ""
                fileURL = nil
            } else {
                displayContent = (try? String(contentsOf: fileURLCandidate, encoding: .utf8)) ?? ""
                fileURL = fileURLCandidate
            }
            readOnly = isReadOnly
        } else if let content = content {
            displayContent = content
            fileURL = nil
            readOnly = true
        } else {
            return // No content provided
        }

        let panel = DisplayPanel(callbackPipePath: validPipe, isReadOnly: readOnly)
        panel.centerTitle()
        panel.setupCloseButtonHover()
        let contentView = DisplayContentView(content: displayContent, fileURL: fileURL, isReadOnly: readOnly)
        panel.contentView = contentView

        let controller = DisplayWindowController(panel: panel)
        controllers[ObjectIdentifier(controller)] = controller
        controller.show()
    }

    func removeController(_ controller: DisplayWindowController) {
        controllers.removeValue(forKey: ObjectIdentifier(controller))
    }

    // MARK: - Validation

    /// Allow callback_pipe paths only under /tmp/ or $TMPDIR.
    private func isValidCallbackPipe(_ path: String) -> Bool {
        let tmpDir = NSTemporaryDirectory()
        return path.hasPrefix("/tmp/") || path.hasPrefix(tmpDir)
    }
}
