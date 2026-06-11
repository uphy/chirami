import AppKit

/// Which optional editor features are available in a given window.
///
/// Pushed to JS via `window.chirami.setCapabilities` so the editor can hide
/// or disable UI for features the host never wires (e.g. the /transcript
/// slash command in Ad-hoc Notes).
struct NoteWebViewCapabilities {
    var transcript: Bool
    var pasteImage: Bool
    var fold: Bool

    static let all = NoteWebViewCapabilities(transcript: true, pasteImage: true, fold: true)
    static let none = NoteWebViewCapabilities(transcript: false, pasteImage: false, fold: false)

    var json: String {
        "{\"transcript\":\(transcript),\"pasteImage\":\(pasteImage),\"fold\":\(fold)}"
    }
}

/// Host of a `NoteWebView`: receives editor callbacks and declares which
/// optional features are available in its window.
///
/// Both `NoteContentModel` (Registered Notes) and `DisplayContentModel`
/// (Ad-hoc Notes) conform, and both Representables wire through
/// `NoteWebView.wireCommonCallbacks(host:)` so a new editor feature only
/// needs to be wired in one place.
@MainActor
protocol NoteWebViewHost: AnyObject {
    var webViewCapabilities: NoteWebViewCapabilities { get }

    // Required callbacks.
    func webViewContentChanged(_ text: String)
    var savedCursorLocation: Int { get set }
    var savedScrollOffset: CGPoint { get set }

    // View-facing accessors assigned during wiring.
    var setWindowActive: ((Bool) -> Void)? { get set }
    var getEditorContext: ((ContextRequestOptions?, @escaping (Result<String, Error>) -> Void) -> Void)? { get set }

    // Capability hooks: only wired when the corresponding capability is enabled.
    func webViewPastedImage(dataUrl: String, insertMarkdown: @escaping (String) -> Void)
    func webViewFoldChanged(lines: [Int])
    var transcriptCoordinator: TranscriptCoordinator? { get }
}

extension NoteWebViewHost {
    func webViewPastedImage(dataUrl: String, insertMarkdown: @escaping (String) -> Void) {}
    func webViewFoldChanged(lines: [Int]) {}
    var transcriptCoordinator: TranscriptCoordinator? { nil }
}
