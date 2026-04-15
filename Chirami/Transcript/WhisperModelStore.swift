import Foundation
import WhisperKit

typealias WhisperModelDownloadProgressHandler = @Sendable (
    _ receivedBytes: Int64,
    _ totalBytes: Int64?,
    _ fractionCompleted: Double
) -> Void
typealias WhisperModelDownloadImplementation = @Sendable (
    _ identifier: String,
    _ downloadBase: URL,
    _ progress: @escaping WhisperModelDownloadProgressHandler
) async throws -> URL

enum WhisperModelStoreError: LocalizedError, Equatable {
    case modelPathIsNotADirectory(URL)
    case modelPathDoesNotExist(URL)
    case failedToCreateDirectory(URL, underlying: String)
    case failedToMoveDownloadedModel(URL, URL, underlying: String)
    case cancelledDownloadingModel(URL)

    var errorDescription: String? {
        switch self {
        case .modelPathIsNotADirectory(let url):
            return "Whisper model path exists but is not a directory: \(url.path)"
        case .modelPathDoesNotExist(let url):
            return "Whisper model path does not exist: \(url.path)"
        case .failedToCreateDirectory(let url, let underlying):
            return "Failed to create Whisper model directory at \(url.path): \(underlying)"
        case .failedToMoveDownloadedModel(let source, let destination, let underlying):
            return "Failed to install Whisper model from \(source.path) to \(destination.path): \(underlying)"
        case .cancelledDownloadingModel(let url):
            return "Whisper model download was cancelled for \(url.path)"
        }
    }
}

final class WhisperModelStore: @unchecked Sendable {
    static let shared = WhisperModelStore()
    private static let defaultRepository = "argmaxinc/whisperkit-coreml"
    private static let defaultDownloadImplementation: WhisperModelDownloadImplementation = { identifier, downloadBase, progress in
        try await WhisperKit.download(
            variant: identifier,
            downloadBase: downloadBase,
            from: defaultRepository,
            progressCallback: { progressState in
                let totalBytes: Int64? = progressState.totalUnitCount > 0 ? progressState.totalUnitCount : nil
                let receivedBytes = progressState.completedUnitCount
                progress(receivedBytes, totalBytes, progressState.fractionCompleted)
            }
        )
    }

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let downloadImplementation: WhisperModelDownloadImplementation

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL = WhisperModelStore.defaultBaseDirectory,
        downloadImplementation: @escaping WhisperModelDownloadImplementation = WhisperModelStore.defaultDownloadImplementation
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
        self.downloadImplementation = downloadImplementation
    }

    static var defaultBaseDirectory: URL {
        FileManager.realHomeDirectory
            .appendingPathComponent(".local/state/chirami/models/whisper", isDirectory: true)
    }

    func isAbsoluteModelPath(_ identifier: String) -> Bool {
        let expanded = (identifier as NSString).expandingTildeInPath
        return expanded.hasPrefix("/")
    }

    func resolvedModelURL(for identifier: String) -> URL {
        if isAbsoluteModelPath(identifier) {
            return URL(fileURLWithPath: (identifier as NSString).expandingTildeInPath)
        }
        return baseDirectory.appendingPathComponent(identifier, isDirectory: true)
    }

    func ensureBaseDirectoryExists() throws {
        try createDirectoryIfNeeded(at: baseDirectory)
    }

    func ensureModelDirectoryExists(for identifier: String) throws -> URL {
        let resolvedURL = resolvedModelURL(for: identifier)
        if isAbsoluteModelPath(identifier) {
            return resolvedURL
        }
        try ensureBaseDirectoryExists()
        try createDirectoryIfNeeded(at: resolvedURL)
        return resolvedURL
    }

    func modelExists(for identifier: String) -> Bool {
        let url = resolvedModelURL(for: identifier)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func downloadModel(
        id identifier: String,
        progress: @escaping WhisperModelDownloadProgressHandler = { _, _, _ in }
    ) async throws -> URL {
        let resolvedURL = resolvedModelURL(for: identifier)

        if isAbsoluteModelPath(identifier) {
            guard modelExists(for: identifier) else {
                throw WhisperModelStoreError.modelPathDoesNotExist(resolvedURL)
            }
            return resolvedURL
        }

        if modelExists(for: identifier) {
            return resolvedURL
        }

        try ensureBaseDirectoryExists()

        let stagingRoot = try makeStagingDirectory()
        var shouldCleanFinalModel = true
        defer {
            if shouldCleanFinalModel {
                try? removeItemIfExists(at: resolvedURL)
            }
            try? removeItemIfExists(at: stagingRoot)
        }

        do {
            let downloadedFolder = try await downloadImplementation(identifier, stagingRoot) {
                receivedBytes,
                totalBytes,
                fractionCompleted in
                progress(receivedBytes, totalBytes, fractionCompleted)
            }
            try installDownloadedModel(from: downloadedFolder, to: resolvedURL)
            shouldCleanFinalModel = false
            return resolvedURL
        } catch is CancellationError {
            throw WhisperModelStoreError.cancelledDownloadingModel(resolvedURL)
        } catch {
            throw error
        }
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw WhisperModelStoreError.modelPathIsNotADirectory(url)
            }
            return
        }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw WhisperModelStoreError.failedToCreateDirectory(url, underlying: error.localizedDescription)
        }
    }

    private func makeStagingDirectory() throws -> URL {
        let stagingRoot = baseDirectory
            .appendingPathComponent(".downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try createDirectoryIfNeeded(at: stagingRoot)
        return stagingRoot
    }

    private func installDownloadedModel(from sourceURL: URL, to destinationURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WhisperModelStoreError.modelPathDoesNotExist(sourceURL)
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try removeItemIfExists(at: destinationURL)
        }

        do {
            try createDirectoryIfNeeded(at: destinationURL.deletingLastPathComponent())
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            throw WhisperModelStoreError.failedToMoveDownloadedModel(sourceURL, destinationURL, underlying: error.localizedDescription)
        }
    }

    private func removeItemIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

}
