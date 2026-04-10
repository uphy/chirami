import AppKit

/// A floating panel for Ad-hoc Notes (CLI-initiated content display), sharing NotePanel's visual style.
class DisplayPanel: NotePanel {

    private var callbackPipeFd: Int32 = -1
    var didNotifyClosed = false

    init(callbackPipePath: String?, isReadOnly: Bool, color: NoteColorScheme = .yellow, transparency: Double = 0.9, customTitle: String? = nil, alwaysOnTop: Bool = true) {
        let frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let baseTitle = customTitle ?? "chirami"
        title = isReadOnly ? "🔒 \(baseTitle)" : baseTitle
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = alwaysOnTop ? .floating : .normal
        isRestorable = false
        backgroundColor = color.nsColor
        alphaValue = transparency

        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // Route all close gestures (ESC, ⌘W, close button) through close(),
        // which ensures notifyClosed() is always called exactly once.
        onHideRequest = { [weak self] in
            self?.close()
        }

        // Open the FIFO early so the Go CLI's read-side gets a writer immediately.
        // If this process is force-quit, the OS closes the fd, producing EOF on the
        // Go side so it can detect the crash and exit.
        if let pipePath = callbackPipePath {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let fd = open(pipePath, O_WRONLY)
                DispatchQueue.main.async {
                    self?.callbackPipeFd = fd
                }
            }
        }
    }

    /// Write CLOSED\n to the callback FIFO if one was provided.
    /// Guaranteed to be called at most once per window lifetime.
    func notifyClosed() {
        guard !didNotifyClosed else { return }
        didNotifyClosed = true
        let fd = callbackPipeFd
        guard fd >= 0,
              let data = "CLOSED\n".data(using: .utf8) else { return }
        callbackPipeFd = -1
        data.withUnsafeBytes { bytes in
            guard let ptr = bytes.baseAddress else { return }
            _ = write(fd, ptr, bytes.count)
        }
        _ = Darwin.close(fd)
    }

    /// Notify the CLI before closing, regardless of how the window is dismissed.
    override func close() {
        notifyClosed()
        super.close()
    }

}
