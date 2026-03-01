import AppKit

/// A floating panel for CLI-initiated content display, sharing NotePanel's visual style.
class DisplayPanel: NotePanel {

    private let callbackPipePath: String?
    private var didNotifyClosed = false

    init(callbackPipePath: String?, isReadOnly: Bool) {
        self.callbackPipePath = callbackPipePath

        let frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = isReadOnly ? "🔒 chirami" : "chirami"
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = .floating
        isRestorable = false

        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // Route all close gestures (ESC, ⌘W, close button) through close(),
        // which ensures notifyClosed() is always called exactly once.
        onHideRequest = { [weak self] in
            self?.close()
        }
    }

    /// Write CLOSED\n to the callback FIFO if one was provided.
    /// Guaranteed to be called at most once per window lifetime.
    func notifyClosed() {
        guard !didNotifyClosed else { return }
        didNotifyClosed = true
        guard let pipePath = callbackPipePath,
              let data = "CLOSED\n".data(using: .utf8) else { return }
        DispatchQueue.global(qos: .utility).async {
            // Blocking open: waits until Go's os.Open(pipePath) is ready to read.
            let fd = open(pipePath, O_WRONLY)
            guard fd >= 0 else { return }
            data.withUnsafeBytes { bytes in
                guard let ptr = bytes.baseAddress else { return }
                _ = write(fd, ptr, bytes.count)
            }
            _ = Darwin.close(fd)
        }
    }

    /// Notify the CLI before closing, regardless of how the window is dismissed.
    override func close() {
        notifyClosed()
        super.close()
    }

    override func becomeKey() {
        super.becomeKey()
        // DisplayContentView uses a plain NSTextView (not MarkdownTextView).
        // super.becomeKey() handles MarkdownTextView; fall back to NSTextView here.
        if let textView = contentView?.firstDescendant(of: NSTextView.self),
           !(textView is MarkdownTextView) {
            makeFirstResponder(textView)
        }
    }
}
