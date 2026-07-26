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
    var onOpenWikiLink: ((String) -> Void)?  // raw target, e.g. "Page|Alias"
    var onPasteImage: ((String) -> Void)?  // dataUrl
    var onPlainPaste: (() -> Void)?
    var onFoldChanged: (([Int]) -> Void)?  // 1-based line numbers
    var onOverlayVisibleChanged: ((Bool) -> Void)?
    var onSearchPanelVisibleChanged: ((Bool) -> Void)?
    var onPluginStateRequest: ((_ pluginId: String) -> Void)?
    var onPluginStateChanged: ((_ pluginId: String, _ stateJson: String) -> Void)?

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
            case "openWikiLink":
                if let target = body["target"] as? String {
                    onOpenWikiLink?(target)
                }
            case "pasteImage":
                if let dataUrl = body["dataUrl"] as? String {
                    onPasteImage?(dataUrl)
                }
            case "plainPaste":
                onPlainPaste?()
            case "foldChanged":
                if let lines = body["foldedLines"] as? [Int] {
                    onFoldChanged?(lines)
                }
            case "overlayVisible":
                if let visible = body["visible"] as? Bool {
                    onOverlayVisibleChanged?(visible)
                }
            case "searchPanelVisible":
                if let visible = body["visible"] as? Bool {
                    onSearchPanelVisibleChanged?(visible)
                }
            case "pluginStateRequest":
                if let pluginId = body["pluginId"] as? String {
                    onPluginStateRequest?(pluginId)
                }
            case "pluginStateChanged":
                if let pluginId = body["pluginId"] as? String,
                   let stateJson = body["stateJson"] as? String {
                    onPluginStateChanged?(pluginId, stateJson)
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
