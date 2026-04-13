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
    var onCursorChanged: ((Int, Int) -> Void)?  // (offset, line)
    var onScrollChanged: ((Double) -> Void)?
    var onOpenLink: ((URL) -> Void)?
    var onFontSizeChange: ((Int) -> Void)?
    var onPasteImage: ((String) -> Void)?  // dataUrl
    var onFoldChanged: (([Int]) -> Void)?  // 1-based line numbers
    var onTldrawOverlayVisibleChanged: ((Bool) -> Void)?

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
            case "cursorChanged":
                if let offset = body["offset"] as? Int, let line = body["line"] as? Int {
                    onCursorChanged?(offset, line)
                }
            case "scrollChanged":
                if let offset = body["offset"] as? Double {
                    onScrollChanged?(offset)
                }
            case "openLink":
                if let urlString = body["url"] as? String, let url = URL(string: urlString) {
                    onOpenLink?(url)
                }
            case "fontSizeChange":
                if let delta = body["delta"] as? Int {
                    onFontSizeChange?(delta)
                }
            case "pasteImage":
                if let dataUrl = body["dataUrl"] as? String {
                    onPasteImage?(dataUrl)
                }
            case "foldChanged":
                if let lines = body["foldedLines"] as? [Int] {
                    onFoldChanged?(lines)
                }
            case "overlayVisible":
                if let visible = body["visible"] as? Bool {
                    onTldrawOverlayVisibleChanged?(visible)
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
