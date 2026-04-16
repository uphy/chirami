import Testing
@testable import Chirami

@Suite("Sherpa model store")
struct SherpaOnnxModelStoreTests {

    @Test("includes Japanese Parakeet model in the built-in catalog")
    func includesJapaneseParakeetModelInCatalog() throws {
        let store = SherpaOnnxModelStore()

        let model = try store.resolvedCatalogModel(for: SherpaOnnxModelStore.parakeetJapaneseModelIdentifier)

        #expect(model.identifier == "sherpa-onnx-nemo-parakeet-tdt_ctc-0.6b-ja-35000-int8")
        #expect(model.kind == .nemoCTC)
        #expect(model.relativeModelPath == "model.int8.onnx")
        #expect(model.relativeTokensPath == "tokens.txt")
        #expect(model.extractedDirectoryName == "sherpa-onnx-nemo-parakeet-tdt_ctc-0.6b-ja-35000-int8")
    }

    @Test("infers model kind from known identifiers and local paths")
    func infersModelKindFromKnownIdentifiersAndLocalPaths() {
        let store = SherpaOnnxModelStore()

        #expect(store.inferModelKind(for: SherpaOnnxModelStore.defaultModelIdentifier) == .senseVoice)
        #expect(store.inferModelKind(for: SherpaOnnxModelStore.parakeetJapaneseModelIdentifier) == .nemoCTC)
        #expect(store.inferModelKind(for: "~/models/sherpa-onnx-nemo-parakeet-tdt_ctc-0.6b-ja-35000-int8") == .nemoCTC)
        #expect(store.inferModelKind(for: "~/models/custom-sense-voice-ja") == .senseVoice)
    }
}
