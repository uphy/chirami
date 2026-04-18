import Foundation
import os
import Darwin

enum PipeIO {
    private static var hasIgnoredSIGPIPE = false

    static func configureProcessWideSignalHandling() {
        guard !hasIgnoredSIGPIPE else { return }
        signal(SIGPIPE, SIG_IGN)
        hasIgnoredSIGPIPE = true
    }

    @discardableResult
    static func write(_ data: Data, to fd: Int32, logger: Logger, context: String) -> Bool {
        var remaining = data.count
        var offset = 0

        return data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return false }

            while remaining > 0 {
                let written = Darwin.write(fd, base.advanced(by: offset), remaining)
                if written > 0 {
                    offset += written
                    remaining -= written
                    continue
                }

                if errno == EPIPE {
                    logger.info("\(context, privacy: .public): callback pipe reader closed before reply")
                } else {
                    let message = String(cString: strerror(errno))
                    logger.error("\(context, privacy: .public): pipe write failed errno=\(errno) \(message, privacy: .public)")
                }
                return false
            }

            return true
        }
    }
}
