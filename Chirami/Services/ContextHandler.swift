import AppKit
import os

enum TranscriptContextMode: String, Codable {
    case full
    case last
    case seconds
}

struct ContextTranscriptOptions: Codable {
    let mode: TranscriptContextMode
    let value: Int?
}

struct ContextRequestOptions: Codable {
    let transcript: ContextTranscriptOptions?
}

/// Handles chirami://context URI requests.
/// Queries the last focused Registered Note's editor for its current context
/// and writes the result to the callback FIFO.
@MainActor
final class ContextHandler {
    static let shared = ContextHandler()
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "ContextHandler")

    private init() {}

    func handle(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let pipePath = components.queryItems?.first(where: { $0.name == "callback_pipe" })?.value,
              isValidCallbackPipe(pipePath) else {
            logger.error("context URI missing or invalid callback_pipe")
            return
        }

        guard let controller = WindowManager.shared.lastFocusedController else {
            writeToPipe(pipePath, message: "NO_FOCUS\n")
            return
        }

        let options = parseOptions(from: components.queryItems ?? [])

        controller.getEditorContext(options: options) { [weak self] result in
            switch result {
            case .success(let json):
                self?.writeToPipe(pipePath, message: "CONTEXT:\(json)\n")
            case .failure(let error):
                self?.logger.error("getEditorContext failed: \(error.localizedDescription, privacy: .public)")
                self?.writeToPipe(pipePath, message: "NO_FOCUS\n")
            }
        }
    }

    private func writeToPipe(_ path: String, message: String) {
        let msg = message
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fd = open(path, O_WRONLY)
            guard fd >= 0 else {
                self?.logger.error("failed to open pipe: \(path, privacy: .public)")
                return
            }
            guard let data = msg.data(using: .utf8) else {
                Darwin.close(fd)
                return
            }
            data.withUnsafeBytes { bytes in
                guard let ptr = bytes.baseAddress else { return }
                _ = write(fd, ptr, bytes.count)
            }
            Darwin.close(fd)
        }
    }

    private func isValidCallbackPipe(_ path: String) -> Bool {
        path.hasPrefix("/tmp/") || path.hasPrefix(NSTemporaryDirectory())
    }

    private func parseOptions(from queryItems: [URLQueryItem]) -> ContextRequestOptions? {
        guard let modeValue = queryItems.first(where: { $0.name == "transcript_mode" })?.value,
              let mode = TranscriptContextMode(rawValue: modeValue)
        else {
            return nil
        }

        let value = queryItems
            .first(where: { $0.name == "transcript_value" })?
            .value
            .flatMap(Int.init)

        switch mode {
        case .full:
            return ContextRequestOptions(
                transcript: ContextTranscriptOptions(mode: .full, value: nil)
            )
        case .last, .seconds:
            guard let value, value > 0 else {
                logger.error("context URI missing valid transcript_value for mode=\(mode.rawValue, privacy: .public)")
                return nil
            }
            return ContextRequestOptions(
                transcript: ContextTranscriptOptions(mode: mode, value: value)
            )
        }
    }
}
