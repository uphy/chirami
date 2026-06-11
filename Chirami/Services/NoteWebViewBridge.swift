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
    var onPasteImage: ((String) -> Void)?  // dataUrl
    var onPlainPaste: (() -> Void)?
    var onFoldChanged: (([Int]) -> Void)?  // 1-based line numbers
    var onOverlayVisibleChanged: ((Bool) -> Void)?
    var onPluginStateRequest: ((_ pluginId: String) -> Void)?
    var onPluginStateChanged: ((_ pluginId: String, _ stateJson: String) -> Void)?
    var onTranscriptRecordStart: ((TranscriptRecordStartMessage) -> Void)?
    var onTranscriptRecordStop: ((TranscriptBlockRange) -> Void)?
    var onTranscriptRecordClear: ((TranscriptBlockRange) -> Void)?
    var onTranscriptLevelMonitorStart: ((TranscriptLevelMonitorStartMessage) -> Void)?
    var onTranscriptLevelMonitorStop: ((TranscriptBlockRange) -> Void)?
    var onTranscriptDevicesRequest: ((TranscriptDevicesRequestMessage) -> Void)?
    var onTranscriptDeviceSelect: ((TranscriptDeviceSelectionMessage) -> Void)?
    var onTranscriptModelRequest: ((TranscriptModelRequestMessage) -> Void)?
    var onTranscriptModelSelect: ((TranscriptModelSelectionMessage) -> Void)?

    private func decodeBody<T: Decodable>(_ body: [String: Any], as type: T.Type) -> T? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        return decoded
    }

    private func decodeRange(_ body: [String: Any]) -> TranscriptBlockRange? {
        guard let range = body["range"] as? [String: Any] else {
            return nil
        }
        return decodeBody(range, as: TranscriptBlockRange.self)
    }

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
            case "pluginStateRequest":
                if let pluginId = body["pluginId"] as? String {
                    onPluginStateRequest?(pluginId)
                }
            case "pluginStateChanged":
                if let pluginId = body["pluginId"] as? String,
                   let stateJson = body["stateJson"] as? String {
                    onPluginStateChanged?(pluginId, stateJson)
                }
            case "transcriptRecordStart":
                if let message: TranscriptRecordStartMessage = decodeBody(body, as: TranscriptRecordStartMessage.self) {
                    onTranscriptRecordStart?(message)
                } else {
                    logger.warning("transcriptRecordStart payload could not be decoded")
                }
            case "transcriptRecordStop":
                if let range = decodeRange(body) {
                    onTranscriptRecordStop?(range)
                } else {
                    logger.warning("transcriptRecordStop payload could not be decoded")
                }
            case "transcriptRecordClear":
                if let range = decodeRange(body) {
                    onTranscriptRecordClear?(range)
                } else {
                    logger.warning("transcriptRecordClear payload could not be decoded")
                }
            case "transcriptLevelMonitorStart":
                if let message: TranscriptLevelMonitorStartMessage = decodeBody(body, as: TranscriptLevelMonitorStartMessage.self) {
                    onTranscriptLevelMonitorStart?(message)
                } else {
                    logger.warning("transcriptLevelMonitorStart payload could not be decoded")
                }
            case "transcriptLevelMonitorStop":
                if let range = decodeRange(body) {
                    onTranscriptLevelMonitorStop?(range)
                } else {
                    logger.warning("transcriptLevelMonitorStop payload could not be decoded")
                }
            case "transcriptDevicesRequest":
                if let request: TranscriptDevicesRequestMessage = decodeBody(body, as: TranscriptDevicesRequestMessage.self) {
                    logger.info("transcriptDevicesRequest source=\(request.source.rawValue, privacy: .public) blockFrom=\(request.range.blockFrom)")
                    onTranscriptDevicesRequest?(request)
                } else {
                    logger.warning("transcriptDevicesRequest payload could not be decoded")
                }
            case "transcriptDeviceSelect":
                if let selection: TranscriptDeviceSelectionMessage = decodeBody(body, as: TranscriptDeviceSelectionMessage.self) {
                    logger.info("transcriptDeviceSelect source=\(selection.source.rawValue, privacy: .public) value=\(selection.value, privacy: .public) blockFrom=\(selection.range.blockFrom)")
                    onTranscriptDeviceSelect?(selection)
                } else {
                    logger.warning("transcriptDeviceSelect payload could not be decoded")
                }
            case "transcriptModelRequest":
                if let request: TranscriptModelRequestMessage = decodeBody(body, as: TranscriptModelRequestMessage.self) {
                    logger.info("transcriptModelRequest blockFrom=\(request.range.blockFrom)")
                    onTranscriptModelRequest?(request)
                } else {
                    logger.warning("transcriptModelRequest payload could not be decoded")
                }
            case "transcriptModelSelect":
                if let selection: TranscriptModelSelectionMessage = decodeBody(body, as: TranscriptModelSelectionMessage.self) {
                    logger.info("transcriptModelSelect value=\(selection.value, privacy: .public) blockFrom=\(selection.range.blockFrom)")
                    onTranscriptModelSelect?(selection)
                } else {
                    logger.warning("transcriptModelSelect payload could not be decoded")
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
