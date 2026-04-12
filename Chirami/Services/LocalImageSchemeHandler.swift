import WebKit
import UniformTypeIdentifiers
import os

final class LocalImageSchemeHandler: NSObject, WKURLSchemeHandler {
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "LocalImageSchemeHandler")

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "io.github.uphy.Chirami", code: -1))
            return
        }

        // chirami-img:///absolute/path/to/image.png
        let rawPath = url.path
        let decoded = rawPath.removingPercentEncoding ?? rawPath

        // Run file I/O on a background thread; WKURLSchemeTask accepts callbacks from any thread
        Task.detached { [logger = self.logger] in
            do {
                let data = try Self.loadImageData(at: decoded)
                let mime = Self.mimeType(for: decoded)
                let response = URLResponse(
                    url: url,
                    mimeType: mime,
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                logger.error("Failed to load image at \(decoded, privacy: .public): \(error.localizedDescription, privacy: .public)")
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func loadImageData(at path: String) throws -> Data {
        let fileURL = URL(fileURLWithPath: path)
        let didStart = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { fileURL.stopAccessingSecurityScopedResource() }
        }
        return try Data(contentsOf: fileURL)
    }

    private static func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension
        if let type = UTType(filenameExtension: ext)?.preferredMIMEType {
            return type
        }
        return "application/octet-stream"
    }
}
