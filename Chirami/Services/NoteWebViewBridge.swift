import Foundation
import WebKit
import os

// WKScriptMessage is annotated @MainActor (WK_SWIFT_UI_ACTOR) in the SDK.
// WebKit guarantees delivery on the main thread, so assumeIsolated is safe.
@MainActor
final class NoteWebViewBridge: NSObject, WKScriptMessageHandler {
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "NoteWebViewBridge")

    var onReady: (() -> Void)?
    var onContentChanged: ((String) -> Void)?

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }
            switch type {
            case "ready":
                logger.debug("JS ready")
                onReady?()
            case "contentChanged":
                if let text = body["text"] as? String {
                    onContentChanged?(text)
                }
            case "log":
                let level = body["level"] as? String ?? "info"
                let msg = body["message"] as? String ?? ""
                logger.log("[JS \(level, privacy: .public)] \(msg, privacy: .public)")
            default:
                logger.warning("unknown message type: \(type, privacy: .public)")
            }
        }
    }
}
