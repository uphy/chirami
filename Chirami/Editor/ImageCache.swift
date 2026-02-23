import AppKit

/// Singleton image cache for inline Markdown images.
/// Loads local file paths synchronously and remote HTTPS URLs asynchronously.
final class ImageCache {
    static let shared = ImageCache()

    private var cache: [String: NSImage] = [:]
    private var pending: Set<String> = []

    private init() {}

    func image(for urlString: String) -> NSImage? {
        cache[urlString]
    }

    /// Load the image for `urlString` if not already cached.
    /// `completion` is called on the main thread when loading finishes (success or failure).
    /// If the image is already cached, `completion` is not called.
    func load(_ urlString: String, completion: @escaping () -> Void) {
        guard cache[urlString] == nil, !pending.contains(urlString) else { return }
        pending.insert(urlString)

        let resolved = urlString.hasPrefix("~/")
            ? (urlString as NSString).expandingTildeInPath
            : urlString

        if resolved.hasPrefix("/") {
            if let image = NSImage(contentsOfFile: resolved) {
                cache[urlString] = image
            }
            pending.remove(urlString)
            DispatchQueue.main.async { completion() }
            return
        }

        guard let url = URL(string: urlString),
              url.scheme == "https" || url.scheme == "http" else {
            pending.remove(urlString)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data, let image = NSImage(data: data) {
                    self.cache[urlString] = image
                }
                self.pending.remove(urlString)
                completion()
            }
        }.resume()
    }
}
