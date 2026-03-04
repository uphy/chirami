import Foundation
import os

enum AttachmentCleanupService {
    private static let logger = Logger(subsystem: "com.uphy.Chirami", category: "AttachmentCleanup")
    /// Scans all notes and deletes orphaned image files (image-*.png) from attachment directories.
    static func cleanupOrphanedAttachments(notes: [Note]) {
        let fm = FileManager.default

        // Group notes by attachmentsDir
        var dirToNotes: [URL: [Note]] = [:]
        for note in notes {
            guard let dir = note.attachmentsDir else { continue }
            dirToNotes[dir, default: []].append(note)
        }

        for (attachmentsDir, groupNotes) in dirToNotes {
            guard fm.fileExists(atPath: attachmentsDir.path) else { continue }

            // Enumerate image-*.png files in the directory
            guard let contents = try? fm.contentsOfDirectory(
                at: attachmentsDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { continue }

            let imageFiles = contents.filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("image-") && name.hasSuffix(".png")
            }
            guard !imageFiles.isEmpty else { continue }

            // Collect all referenced image paths from note files
            var referencedPaths: Set<String> = []
            for note in groupNotes {
                let noteFiles = listNoteFiles(for: note)
                for noteFile in noteFiles {
                    guard let content = try? String(contentsOf: noteFile, encoding: .utf8) else { continue }
                    let paths = extractImagePaths(from: content)
                    let noteDir = noteFile.deletingLastPathComponent()
                    for path in paths {
                        let resolved = resolveImagePath(path, relativeTo: noteDir)
                        referencedPaths.insert(resolved)
                    }
                }
            }

            // Delete orphaned files
            var deletedCount = 0
            for imageFile in imageFiles {
                let canonicalPath = imageFile.standardizedFileURL.path
                if !referencedPaths.contains(canonicalPath) {
                    do {
                        try fm.removeItem(at: imageFile)
                        deletedCount += 1
                    } catch {
                        logger.error("Failed to delete orphaned image: \(imageFile.path, privacy: .public), error: \(error, privacy: .public)")
                    }
                }
            }
            if deletedCount > 0 {
                logger.info("Cleaned up \(deletedCount, privacy: .public) orphaned image(s) from \(attachmentsDir.path, privacy: .public)")
            }
        }
    }

    /// Extracts image paths from Markdown ![...](...) syntax.
    static func extractImagePaths(from content: String) -> [String] {
        // Match ![any alt text](path) — path must not contain )
        guard let regex = try? NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\(([^)]+)\\)") else {
            return []
        }
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)
        let matches = regex.matches(in: content, range: range)
        return matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let pathRange = match.range(at: 1)
            guard pathRange.location != NSNotFound else { return nil }
            return nsContent.substring(with: pathRange)
        }
    }

    // MARK: - Private

    /// Lists all note files for a given note. For periodic notes, enumerates all matching files.
    private static func listNoteFiles(for note: Note) -> [URL] {
        if let periodicInfo = note.periodicInfo {
            let baseDir = PathTemplateResolver.extractBaseDirectory(from: periodicInfo.pathTemplate)
            let baseDirURL: URL
            if baseDir.hasPrefix("~/") {
                baseDirURL = URL(fileURLWithPath: (baseDir as NSString).expandingTildeInPath)
            } else if baseDir.hasPrefix("/") {
                baseDirURL = URL(fileURLWithPath: baseDir)
            } else {
                baseDirURL = note.path.deletingLastPathComponent()
            }
            // Extract the relative template portion after the base directory
            let relativeTemplate = String(periodicInfo.pathTemplate.dropFirst(baseDir.count))
            return PeriodicFileNavigator.listMatchingFiles(template: relativeTemplate, baseDirectory: baseDirURL)
        }
        return [note.path]
    }

    /// Resolves a potentially relative image path against a note's directory.
    private static func resolveImagePath(_ path: String, relativeTo noteDir: URL) -> String {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        return noteDir.appendingPathComponent(path).standardizedFileURL.path
    }
}
