import AppKit
import Foundation
import os

/// A window controller that can provide the current editor context.
@MainActor
protocol EditorContextProvider: AnyObject {
    func getEditorContext(completion: @escaping (Result<String, Error>) -> Void)
}

struct EditorContextPosition: Codable {
    let line: Int
    let column: Int
}

struct EditorContextSelection: Codable {
    let text: String
    let from: EditorContextPosition
    let to: EditorContextPosition
}

struct EditorContextPayload: Codable {
    let file: String
    let selection: EditorContextSelection
    let cursor: EditorContextPosition
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

        guard let controller = WindowManager.shared.lastFocusedEditorProvider else {
            writeToPipe(pipePath, message: "NO_FOCUS\n")
            return
        }

        controller.getEditorContext { [weak self] result in
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
            PipeIO.write(data, to: fd, logger: self?.logger ?? Logger(subsystem: "io.github.uphy.Chirami", category: "ContextHandler"), context: "ContextHandler.writeToPipe")
            Darwin.close(fd)
        }
    }

    private func isValidCallbackPipe(_ path: String) -> Bool {
        path.hasPrefix("/tmp/") || path.hasPrefix(NSTemporaryDirectory())
    }
}
