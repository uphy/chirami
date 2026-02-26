import AppKit
import CryptoKit

struct ImagePasteResult {
    let fileURL: URL
    let markdownText: String
}

enum ImagePasteError: Error {
    case pngConversionFailed
    case fileWriteFailed(Error)
    case directoryCreationFailed(Error)
}

struct ImagePasteService {

    func save(image: NSImage, to attachmentsDir: URL, noteURL: URL) -> Result<ImagePasteResult, ImagePasteError> {
        // Convert to PNG data
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return .failure(.pngConversionFailed)
        }

        // Generate filename from SHA256 hash prefix (16 bytes = 32 hex chars)
        let digest = SHA256.hash(data: pngData)
        let hashPrefix = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let filename = "image-\(hashPrefix).png"
        let fileURL = attachmentsDir.appendingPathComponent(filename)

        // Create directory if needed
        if !FileManager.default.fileExists(atPath: attachmentsDir.path) {
            do {
                try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
            } catch {
                return .failure(.directoryCreationFailed(error))
            }
        }

        // Write file only if it doesn't already exist (deduplication)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try pngData.write(to: fileURL)
            } catch {
                return .failure(.fileWriteFailed(error))
            }
        }

        // Calculate relative path from note to attachment
        let relativePath = Self.relativePath(from: noteURL, to: fileURL)
        let markdownText = "![](\(relativePath))"

        return .success(ImagePasteResult(fileURL: fileURL, markdownText: markdownText))
    }

    /// Calculates a relative path from a note file to a target file.
    static func relativePath(from noteURL: URL, to targetURL: URL) -> String {
        let noteDir = noteURL.deletingLastPathComponent().standardizedFileURL.path
        let targetPath = targetURL.standardizedFileURL.path

        // If target is under note's directory, return simple relative path
        if targetPath.hasPrefix(noteDir + "/") {
            return String(targetPath.dropFirst(noteDir.count + 1))
        }

        // Build relative path by walking up from noteDir
        let noteComponents = noteDir.components(separatedBy: "/").filter { !$0.isEmpty }
        let targetComponents = targetPath.components(separatedBy: "/").filter { !$0.isEmpty }

        // Find common prefix length
        var commonLen = 0
        for i in 0..<min(noteComponents.count, targetComponents.count) {
            if noteComponents[i] == targetComponents[i] {
                commonLen = i + 1
            } else {
                break
            }
        }

        let upCount = noteComponents.count - commonLen
        let upPath = Array(repeating: "..", count: upCount)
        let downPath = Array(targetComponents[commonLen...])
        return (upPath + downPath).joined(separator: "/")
    }
}
