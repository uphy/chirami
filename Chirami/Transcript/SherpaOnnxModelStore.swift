import Foundation

typealias SherpaOnnxModelDownloadProgressHandler = @Sendable (
    _ receivedBytes: Int64,
    _ totalBytes: Int64?,
    _ fractionCompleted: Double,
    _ stage: TranscriptDownloadStage
) -> Void

enum SherpaOnnxModelKind: String, Sendable, Equatable {
    case senseVoice
    case nemoCTC

    static func inferred(from identifier: String) -> Self {
        let normalized = identifier.lowercased()
        if normalized.contains("parakeet") || normalized.contains("nemo-") || normalized.contains("nemo_") {
            return .nemoCTC
        }
        return .senseVoice
    }
}

enum SherpaOnnxModelStoreError: LocalizedError, Equatable {
    case unsupportedModelIdentifier(String)
    case modelPathIsNotADirectory(URL)
    case modelPathDoesNotExist(URL)
    case failedToCreateDirectory(URL, underlying: String)
    case failedToExtractArchive(URL, underlying: String)
    case failedToMoveDownloadedModel(URL, URL, underlying: String)
    case cancelledDownloadingModel(URL)
    case invalidDownloadedArchive(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedModelIdentifier(let identifier):
            return "Unsupported sherpa-onnx model identifier: \(identifier)"
        case .modelPathIsNotADirectory(let url):
            return "Sherpa model path exists but is not a directory: \(url.path)"
        case .modelPathDoesNotExist(let url):
            return "Sherpa model path does not exist: \(url.path)"
        case .failedToCreateDirectory(let url, let underlying):
            return "Failed to create Sherpa model directory at \(url.path): \(underlying)"
        case .failedToExtractArchive(let url, let underlying):
            return "Failed to extract Sherpa model archive \(url.lastPathComponent): \(underlying)"
        case .failedToMoveDownloadedModel(let source, let destination, let underlying):
            return "Failed to install Sherpa model from \(source.path) to \(destination.path): \(underlying)"
        case .cancelledDownloadingModel(let url):
            return "Sherpa model download was cancelled for \(url.path)"
        case .invalidDownloadedArchive(let url):
            return "Sherpa model archive did not contain the expected directory: \(url.path)"
        }
    }
}

final class SherpaOnnxModelStore: @unchecked Sendable {
    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        let progress: SherpaOnnxModelDownloadProgressHandler
        let destinationURL: URL
        var continuation: CheckedContinuation<(URL, URLResponse), Error>?
        var downloadedURL: URL?
        var response: URLResponse?

        init(destinationURL: URL, progress: @escaping SherpaOnnxModelDownloadProgressHandler) {
            self.destinationURL = destinationURL
            self.progress = progress
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
            let fractionCompleted =
                expected.map { Double(totalBytesWritten) / Double($0) } ?? 0
            progress(totalBytesWritten, expected, fractionCompleted, .downloading)
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            do {
                let fileManager = FileManager.default
                try? fileManager.removeItem(at: destinationURL)
                try fileManager.moveItem(at: location, to: destinationURL)
                downloadedURL = destinationURL
            } catch {
                guard let continuation else {
                    return
                }
                self.continuation = nil
                continuation.resume(throwing: error)
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            defer {
                session.finishTasksAndInvalidate()
            }

            guard let continuation else {
                return
            }
            self.continuation = nil

            if let error {
                continuation.resume(throwing: error)
                return
            }

            guard let downloadedURL, let response = task.response ?? response else {
                continuation.resume(throwing: URLError(.badServerResponse))
                return
            }

            continuation.resume(returning: (downloadedURL, response))
        }

    }

    struct CatalogModel: Equatable {
        let identifier: String
        let kind: SherpaOnnxModelKind
        let label: String
        let detail: String?
        let supportedLanguages: [String]
        let archiveURL: URL
        let extractedDirectoryName: String
        let relativeModelPath: String
        let relativeTokensPath: String
    }

    static let shared = SherpaOnnxModelStore()
    static let defaultModelIdentifier = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
    static let parakeetJapaneseModelIdentifier = "sherpa-onnx-nemo-parakeet-tdt_ctc-0.6b-ja-35000-int8"

    private static let catalog: [String: CatalogModel] = [
        defaultModelIdentifier: CatalogModel(
            identifier: defaultModelIdentifier,
            kind: .senseVoice,
            label: "SenseVoice",
            detail: "Multilingual Japanese/English meeting model",
            supportedLanguages: ["zh", "en", "ja", "ko", "yue"],
            archiveURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2")!,
            extractedDirectoryName: defaultModelIdentifier,
            relativeModelPath: "model.int8.onnx",
            relativeTokensPath: "tokens.txt"
        ),
        parakeetJapaneseModelIdentifier: CatalogModel(
            identifier: parakeetJapaneseModelIdentifier,
            kind: .nemoCTC,
            label: "Parakeet Japanese",
            detail: "Japanese-focused ReazonSpeech 35k-hour model",
            supportedLanguages: ["ja"],
            archiveURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt_ctc-0.6b-ja-35000-int8.tar.bz2")!,
            extractedDirectoryName: parakeetJapaneseModelIdentifier,
            relativeModelPath: "model.int8.onnx",
            relativeTokensPath: "tokens.txt"
        )
    ]

    private let fileManager: FileManager
    private let baseDirectory: URL

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL = SherpaOnnxModelStore.defaultBaseDirectory
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    static var defaultBaseDirectory: URL {
        FileManager.realHomeDirectory
            .appendingPathComponent(".local/state/chirami/models/sherpa-onnx", isDirectory: true)
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

    func inferModelKind(for identifier: String) -> SherpaOnnxModelKind {
        if let model = Self.catalog[identifier] {
            return model.kind
        }
        return SherpaOnnxModelKind.inferred(from: identifier)
    }

    func builtInModels() -> [CatalogModel] {
        [
            Self.catalog[Self.defaultModelIdentifier],
            Self.catalog[Self.parakeetJapaneseModelIdentifier]
        ]
        .compactMap { $0 }
    }

    func modelExists(for identifier: String) -> Bool {
        let url = resolvedModelURL(for: identifier)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        if isAbsoluteModelPath(identifier) {
            return true
        }
        guard let model = Self.catalog[identifier] else {
            return false
        }
        return fileManager.fileExists(atPath: url.appendingPathComponent(model.relativeModelPath).path) &&
            fileManager.fileExists(atPath: url.appendingPathComponent(model.relativeTokensPath).path)
    }

    func installedSizeBytes(for identifier: String) -> Int64? {
        let url = resolvedModelURL(for: identifier)
        guard modelExists(for: identifier) else {
            return nil
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total > 0 ? total : nil
    }

    func resolvedCatalogModel(for identifier: String) throws -> CatalogModel {
        if let model = Self.catalog[identifier] {
            return model
        }
        throw SherpaOnnxModelStoreError.unsupportedModelIdentifier(identifier)
    }

    func downloadModel(
        id identifier: String,
        progress: @escaping SherpaOnnxModelDownloadProgressHandler = { _, _, _, _ in }
    ) async throws -> URL {
        let resolvedURL = resolvedModelURL(for: identifier)

        if isAbsoluteModelPath(identifier) {
            guard modelExists(for: identifier) else {
                throw SherpaOnnxModelStoreError.modelPathDoesNotExist(resolvedURL)
            }
            return resolvedURL
        }

        if modelExists(for: identifier) {
            return resolvedURL
        }

        let model = try resolvedCatalogModel(for: identifier)
        try ensureBaseDirectoryExists()

        let stagingRoot = try makeStagingDirectory()
        let archiveURL = stagingRoot.appendingPathComponent("\(model.identifier).tar.bz2")
        let extractionRoot = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
        var shouldCleanFinalModel = true
        defer {
            if shouldCleanFinalModel {
                try? removeItemIfExists(at: resolvedURL)
            }
            try? removeItemIfExists(at: stagingRoot)
        }

        do {
            progress(0, -1, 0, .downloading)
            let (temporaryArchiveURL, response) = try await downloadArchive(from: model.archiveURL, to: archiveURL, progress: progress)
            let totalBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
            if temporaryArchiveURL.path != archiveURL.path {
                try removeItemIfExists(at: archiveURL)
                try fileManager.moveItem(at: temporaryArchiveURL, to: archiveURL)
            }
            progress(totalBytes ?? 0, totalBytes, totalBytes == nil ? 0 : 1, .installing)

            try createDirectoryIfNeeded(at: extractionRoot)
            try extract(archiveURL: archiveURL, into: extractionRoot)

            let extractedURL = extractionRoot.appendingPathComponent(model.extractedDirectoryName, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: extractedURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw SherpaOnnxModelStoreError.invalidDownloadedArchive(extractedURL)
            }

            try installDownloadedModel(from: extractedURL, to: resolvedURL)
            progress(totalBytes ?? 0, totalBytes, 1, .installing)
            shouldCleanFinalModel = false
            return resolvedURL
        } catch is CancellationError {
            throw SherpaOnnxModelStoreError.cancelledDownloadingModel(resolvedURL)
        } catch {
            throw error
        }
    }

    private func ensureBaseDirectoryExists() throws {
        try createDirectoryIfNeeded(at: baseDirectory)
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw SherpaOnnxModelStoreError.modelPathIsNotADirectory(url)
            }
            return
        }

        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw SherpaOnnxModelStoreError.failedToCreateDirectory(url, underlying: error.localizedDescription)
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
        if fileManager.fileExists(atPath: destinationURL.path) {
            try removeItemIfExists(at: destinationURL)
        }

        do {
            try createDirectoryIfNeeded(at: destinationURL.deletingLastPathComponent())
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            throw SherpaOnnxModelStoreError.failedToMoveDownloadedModel(sourceURL, destinationURL, underlying: error.localizedDescription)
        }
    }

    private func downloadArchive(
        from url: URL,
        to destinationURL: URL,
        progress: @escaping SherpaOnnxModelDownloadProgressHandler
    ) async throws -> (URL, URLResponse) {
        let delegate = DownloadDelegate(destinationURL: destinationURL, progress: progress)
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    private func extract(archiveURL: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archiveURL.path, "-C", directory.path]
        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw SherpaOnnxModelStoreError.failedToExtractArchive(archiveURL, underlying: error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SherpaOnnxModelStoreError.failedToExtractArchive(
                archiveURL,
                underlying: message?.isEmpty == false ? message! : "tar exited with status \(process.terminationStatus)"
            )
        }
    }

    private func removeItemIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }
}
