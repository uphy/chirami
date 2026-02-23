import Foundation

/// Watches a file for external changes using DispatchSource.
/// Automatically restarts after atomic writes (delete+rename) that invalidate the file descriptor.
class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let url: URL
    private let onChange: () -> Void
    private var isActive = true

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start(notifyOnSuccess: false)
    }

    /// Opens a new file descriptor and sets up the watcher.
    /// - Parameter notifyOnSuccess: If true, calls onChange() once the fd is successfully opened.
    ///   Used after atomic writes so that onChange fires only when the new file is actually readable.
    private func start(notifyOnSuccess: Bool) {
        stop()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File may not exist yet (e.g. between delete and rename in atomic write); retry
            retryStart()
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )
        self.source = source

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = source.data

            if flags.contains(.delete) || flags.contains(.rename) {
                // Atomic write replaced the file; restart watcher with new fd.
                // Notify onChange only after the new file is confirmed readable.
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self, self.isActive else { return }
                    self.start(notifyOnSuccess: true)
                }
            } else {
                self.onChange()
            }
        }

        // Capture fd by value so the cancel handler closes the correct descriptor,
        // not self.fileDescriptor which may already point to a newer fd.
        source.setCancelHandler {
            close(fd)
        }

        source.resume()

        if notifyOnSuccess {
            onChange()
        }
    }

    private func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    private func retryStart() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.isActive else { return }
            // notifyOnSuccess: true — the file should exist now; trigger a reload once open succeeds
            self.start(notifyOnSuccess: true)
        }
    }

    deinit {
        isActive = false
        stop()
    }
}
