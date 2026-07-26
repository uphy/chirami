import Foundation
import os

/// Watches a directory for changes (file creation, deletion, rename) using DispatchSource.
/// Events are debounced so bursts of filesystem activity coalesce into a single callback.
/// Unlike `FileWatcher`, this only reports "the directory changed" — it does not
/// diff the directory listing; the caller is responsible for figuring out what changed.
class DirectoryWatcher {
    private static let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "DirectoryWatcher")

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let url: URL
    private let debounceInterval: TimeInterval
    private let onChange: () -> Void

    /// Guards `isActive` and `pendingWorkItem`, which are touched both by the caller
    /// (start/stop) and by the DispatchSource event handler on a background queue.
    private let lock = NSLock()
    private var isActive = false
    private var pendingWorkItem: DispatchWorkItem?

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isActive
    }

    /// - Parameters:
    ///   - url: The directory to watch.
    ///   - debounceInterval: How long to wait after the last event before firing onChange.
    ///     Defaults to 200ms per the stream-note-mode design.
    ///   - onChange: Called on the main queue once per debounced burst of changes.
    init(url: URL, debounceInterval: TimeInterval = 0.2, onChange: @escaping () -> Void) {
        self.url = url
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    /// Opens a file descriptor on the directory and starts watching.
    /// - Returns: true if the watcher started successfully, false if the directory
    ///   does not exist (or cannot be opened).
    @discardableResult
    func start() -> Bool {
        stop()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            Self.logger.warning("Directory does not exist or cannot be opened: \(self.url.path, privacy: .public)")
            return false
        }
        fileDescriptor = fd
        lock.lock()
        isActive = true
        lock.unlock()

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: DispatchQueue.global(qos: .utility)
        )
        self.source = source

        source.setEventHandler { [weak self] in
            self?.scheduleDebouncedNotification()
        }

        // Capture fd by value so the cancel handler closes the correct descriptor,
        // not self.fileDescriptor which may already point to a newer fd.
        source.setCancelHandler {
            close(fd)
        }

        source.resume()

        Self.logger.debug("Started watching directory: \(self.url.path, privacy: .public)")
        return true
    }

    /// Cancels the watcher and any pending debounced notification.
    func stop() {
        lock.lock()
        let wasActive = isActive
        isActive = false
        let pending = pendingWorkItem
        pendingWorkItem = nil
        lock.unlock()

        guard wasActive || source != nil else { return }

        pending?.cancel()
        source?.cancel()
        source = nil
        fileDescriptor = -1
        Self.logger.debug("Stopped watching directory: \(self.url.path, privacy: .public)")
    }

    private func scheduleDebouncedNotification() {
        Self.logger.debug("Directory event received: \(self.url.path, privacy: .public)")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.onChange()
        }

        lock.lock()
        // An event already in flight when stop() ran must not re-arm the timer.
        guard isActive else {
            lock.unlock()
            return
        }
        pendingWorkItem?.cancel()
        pendingWorkItem = workItem
        lock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    deinit {
        stop()
    }
}
