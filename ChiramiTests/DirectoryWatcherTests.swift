import Testing
import Foundation
@testable import Chirami

/// Thread-safe counter used to observe DirectoryWatcher callbacks, which fire on the main queue
/// while tests may run on a different thread.
private final class ChangeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func record() {
        lock.lock()
        _count += 1
        lock.unlock()
    }
}

@Suite("DirectoryWatcher")
struct DirectoryWatcherTests {
    @Test("new file creation triggers the callback")
    func newFileTriggersCallback() async throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = ChangeRecorder()
        let watcher = DirectoryWatcher(url: dir, debounceInterval: 0.05) {
            recorder.record()
        }
        #expect(watcher.start())
        defer { watcher.stop() }

        try createFile(at: dir.appendingPathComponent("a.md"))

        try await waitUntil(timeout: 2.0) { recorder.count >= 1 }
        #expect(recorder.count == 1)
    }

    @Test("a burst of rapid file creations yields a single debounced callback")
    func burstIsDebounced() async throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = ChangeRecorder()
        // The debounce window has to stay far wider than the gap between events: on a loaded
        // CI runner a 10ms sleep can overshoot by an order of magnitude, and any gap that
        // exceeds the window splits the burst into two callbacks.
        let watcher = DirectoryWatcher(url: dir, debounceInterval: 1.0) {
            recorder.record()
        }
        #expect(watcher.start())
        defer { watcher.stop() }

        // Fire several rapid changes without waiting for the debounce window to elapse.
        for i in 0..<5 {
            try createFile(at: dir.appendingPathComponent("burst-\(i).md"))
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms between events, well under the 1s debounce
        }

        // Give the debounce window a generous margin to settle after the last event.
        try await Task.sleep(nanoseconds: 2_000_000_000)

        #expect(recorder.count == 1)
    }

    @Test("stop prevents further callbacks")
    func stopPreventsFurtherCallbacks() async throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = ChangeRecorder()
        let watcher = DirectoryWatcher(url: dir, debounceInterval: 0.05) {
            recorder.record()
        }
        #expect(watcher.start())

        try createFile(at: dir.appendingPathComponent("a.md"))
        try await waitUntil(timeout: 2.0) { recorder.count >= 1 }
        #expect(recorder.count == 1)

        watcher.stop()

        try createFile(at: dir.appendingPathComponent("b.md"))
        // No further callback should fire; wait past the debounce window to be sure.
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(recorder.count == 1)
    }

    @Test("stopping during the debounce window suppresses the pending callback")
    func stopDuringDebounceWindowSuppressesCallback() async throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = ChangeRecorder()
        // Wide enough that a slow runner cannot let the debounce fire before stop() lands.
        let watcher = DirectoryWatcher(url: dir, debounceInterval: 2.0) {
            recorder.record()
        }
        #expect(watcher.start())

        try createFile(at: dir.appendingPathComponent("a.md"))
        // Stop well before the 2s debounce window elapses.
        try await Task.sleep(nanoseconds: 100_000_000)
        watcher.stop()

        try await Task.sleep(nanoseconds: 2_500_000_000)

        #expect(recorder.count == 0)
    }

    @Test("start returns false when the directory does not exist")
    func startFailsForMissingDirectory() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryWatcherTests-missing-\(UUID().uuidString)")

        let watcher = DirectoryWatcher(url: missing) {}
        #expect(watcher.start() == false)
    }

    // MARK: - Helpers

    private func createTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createFile(at url: URL) throws {
        try "".write(to: url, atomically: true, encoding: .utf8)
    }

    /// Polls `condition` until it becomes true or `timeout` elapses.
    private func waitUntil(
        timeout: TimeInterval,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
