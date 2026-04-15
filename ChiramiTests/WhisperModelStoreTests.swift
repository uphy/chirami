import Foundation
import Testing
@testable import Chirami

final class AnyBox<T>: @unchecked Sendable {
    var value: T?
}

@Suite("Whisper model store")
struct WhisperModelStoreTests {

    @Test("resolves managed model directory under chirami state")
    func resolvesManagedModelDirectory() {
        let baseURL = URL(fileURLWithPath: "/tmp/chirami-models")
        let store = WhisperModelStore(baseDirectory: baseURL)

        let resolved = store.resolvedModelURL(for: "openai_whisper-large-v3_turbo")
        #expect(resolved.path == "/tmp/chirami-models/openai_whisper-large-v3_turbo")
        #expect(store.isAbsoluteModelPath("openai_whisper-large-v3_turbo") == false)
    }

    @Test("resolves absolute model path without rewriting")
    func resolvesAbsoluteModelPath() {
        let store = WhisperModelStore(baseDirectory: URL(fileURLWithPath: "/tmp/chirami-models"))

        let resolved = store.resolvedModelURL(for: "~/models/whisper-small")
        #expect(store.isAbsoluteModelPath("~/models/whisper-small"))
        #expect(resolved.path.hasSuffix("/models/whisper-small"))
    }

    @Test("creates managed model directory on demand")
    func createsManagedModelDirectory() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = WhisperModelStore(baseDirectory: tempRoot)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        #expect(store.modelExists(for: "openai_whisper-small") == false)
        let resolved = try store.ensureModelDirectoryExists(for: "openai_whisper-small")
        #expect(resolved.path == tempRoot.appendingPathComponent("openai_whisper-small", isDirectory: true).path)
        #expect(store.modelExists(for: "openai_whisper-small"))
    }

    @Test("downloads managed model into the configured state directory")
    func downloadsManagedModelIntoStateDirectory() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let seenDownloadBase = AnyBox<URL>()
        let seenIdentifier = AnyBox<String>()
        let store = WhisperModelStore(
            fileManager: .default,
            baseDirectory: tempRoot,
            downloadImplementation: { identifier, downloadBase, progress in
                seenIdentifier.value = identifier
                seenDownloadBase.value = downloadBase
                let modelFolder = downloadBase.appendingPathComponent(identifier, isDirectory: true)
                try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
                try "compiled-model".write(
                    to: modelFolder.appendingPathComponent("model.mlmodelc"),
                    atomically: true,
                    encoding: .utf8
                )
                progress(128, 256, 0.5)
                return modelFolder
            }
        )
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let resolved = try await store.downloadModel(id: "openai_whisper-small")
        let expected = tempRoot.appendingPathComponent("openai_whisper-small", isDirectory: true)
        #expect(resolved == expected)
        #expect(FileManager.default.fileExists(atPath: expected.path))
        #expect(seenDownloadBase.value?.lastPathComponent != nil)
        #expect(seenDownloadBase.value?.path.contains(".downloads") == true)
        #expect(seenIdentifier.value == "openai_whisper-small")
    }


    @Test("cleans up partial downloads when cancellation is thrown")
    func cleansUpPartialDownloadsOnCancellation() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagingDirectory = AnyBox<URL>()
        let store = WhisperModelStore(
            fileManager: .default,
            baseDirectory: tempRoot,
            downloadImplementation: { _, downloadBase, _ in
                stagingDirectory.value = downloadBase
                let partial = downloadBase.appendingPathComponent("partial", isDirectory: true)
                try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
                throw CancellationError()
            }
        )
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        do {
            _ = try await store.downloadModel(id: "openai_whisper-small")
            #expect(Bool(false))
        } catch WhisperModelStoreError.cancelledDownloadingModel(let url) {
            #expect(url.path == tempRoot.appendingPathComponent("openai_whisper-small", isDirectory: true).path)
        }

        #expect(stagingDirectory.value.map { FileManager.default.fileExists(atPath: $0.path) } == Optional(false))
        #expect(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("openai_whisper-small", isDirectory: true).path) == false)
    }

    @Test("uses absolute model paths directly without downloading")
    func usesAbsoluteModelPathsDirectlyWithoutDownloading() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let absoluteModelFolder = tempRoot.appendingPathComponent("manual-model", isDirectory: true)
        try FileManager.default.createDirectory(at: absoluteModelFolder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let invokedDownloader = AnyBox<Bool>()
        let store = WhisperModelStore(
            fileManager: .default,
            baseDirectory: tempRoot,
            downloadImplementation: { _, _, _ in
                invokedDownloader.value = true
                throw CancellationError()
            }
        )

        let resolved = try await store.downloadModel(id: absoluteModelFolder.path)
        #expect(resolved == absoluteModelFolder)
        #expect(invokedDownloader.value == nil)
    }
}
