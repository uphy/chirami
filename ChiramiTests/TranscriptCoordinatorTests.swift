import Foundation
import Testing
@testable import Chirami

// MARK: - Mocks and fixtures

@MainActor
private final class MockTranscriptMessageSink: TranscriptMessageSink {
    var chunks: [TranscriptChunkMessage] = []
    var previews: [TranscriptPreviewMessage] = []
    var states: [TranscriptStateMessage] = []
    var levels: [TranscriptLevelUpdateMessage] = []
    var devicesLists: [TranscriptDevicesListMessage] = []
    var modelStates: [TranscriptModelStateMessage] = []
    var downloadProgress: [TranscriptModelDownloadProgressMessage] = []
    var errors: [TranscriptErrorMessage] = []

    func transcriptChunk(_ chunk: TranscriptChunkMessage) {
        chunks.append(chunk)
    }

    func transcriptPreviewUpdate(_ preview: TranscriptPreviewMessage) {
        previews.append(preview)
    }

    func transcriptStateChanged(_ state: TranscriptStateMessage) {
        states.append(state)
    }

    func transcriptLevelUpdate(_ update: TranscriptLevelUpdateMessage) {
        levels.append(update)
    }

    func transcriptDevicesList(_ message: TranscriptDevicesListMessage) {
        devicesLists.append(message)
    }

    func transcriptModelState(_ message: TranscriptModelStateMessage) {
        modelStates.append(message)
    }

    func transcriptModelDownloadProgress(_ message: TranscriptModelDownloadProgressMessage) {
        downloadProgress.append(message)
    }

    func transcriptError(_ message: TranscriptErrorMessage) {
        errors.append(message)
    }
}

/// Builds a `TranscriptCoordinator` with every dependency injected explicitly.
/// Never rely on the coordinator initializer's default arguments in tests:
/// they read and write the developer's real config.yaml / state.yaml.
@MainActor
private final class CoordinatorFixture {
    let sink = MockTranscriptMessageSink()
    var config: TranscriptConfig
    var state: TranscriptStateSnapshot
    var devices: [AudioDeviceDescriptor]
    var defaultDevice: AudioDeviceDescriptor?
    var processes: [AudioProcessDescriptor]
    private(set) var selectedModels: [String] = []
    private(set) var deviceCacheUpdates: [(lastMic: String?, lastSystemSource: String?)] = []
    let modelStore: SherpaOnnxModelStore

    init(
        config: TranscriptConfig = TranscriptConfig(),
        state: TranscriptStateSnapshot = TranscriptStateSnapshot(),
        devices: [AudioDeviceDescriptor] = [],
        defaultDevice: AudioDeviceDescriptor? = nil,
        processes: [AudioProcessDescriptor] = []
    ) {
        self.config = config
        self.state = state
        self.devices = devices
        self.defaultDevice = defaultDevice
        self.processes = processes
        // Point the model store at a non-existent temporary directory so
        // modelExists is always false and nothing touches the real state dir.
        self.modelStore = SherpaOnnxModelStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("chirami-coordinator-tests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    func makeCoordinator() -> TranscriptCoordinator {
        let coordinator = TranscriptCoordinator(
            transcriptConfig: { [self] in config },
            configDirectory: { FileManager.default.temporaryDirectory },
            stateSnapshot: { [self] in state },
            updateDeviceCache: { [self] lastMic, lastSystemSource in
                deviceCacheUpdates.append((lastMic: lastMic, lastSystemSource: lastSystemSource))
            },
            setTranscriptModel: { [self] identifier in
                selectedModels.append(identifier)
                // Mirror AppState.setTranscriptModel: subsequent snapshots
                // observe the newly selected model.
                state.transcriptModel = identifier
            },
            audioInputDevices: { [self] in devices },
            defaultAudioInputDevice: { [self] in defaultDevice },
            runningOutputProcesses: { [self] in processes },
            modelStore: modelStore,
            sessionRegistry: TranscriptSessionRegistry()
        )
        coordinator.sink = sink
        return coordinator
    }
}

private let builtInMic = AudioDeviceDescriptor(uniqueID: "builtin-mic", name: "Built-in Microphone")
private let usbMic = AudioDeviceDescriptor(uniqueID: "usb-mic", name: "USB Microphone")
private let zoomProcess = AudioProcessDescriptor(
    objectID: 1,
    pid: 42,
    bundleID: "us.zoom.xos",
    applicationName: "Zoom",
    isRunningInput: false,
    isRunningOutput: true
)
private let testRange = TranscriptBlockRange(blockFrom: 3, blockTo: 9)

// MARK: - Tests

@Suite("Transcript coordinator")
@MainActor
struct TranscriptCoordinatorTests {
    // MARK: Mic device options

    @Test("mic options: default selection marks the default entry active")
    func micOptionsDefaultSelection() {
        let fixture = CoordinatorFixture(devices: [usbMic, builtInMic], defaultDevice: builtInMic)
        let coordinator = fixture.makeCoordinator()

        let options = coordinator.micDeviceOptions(selectedValue: "default")

        // Devices are sorted by name; the "default" entry stays first.
        #expect(options.map(\.value) == ["default", "builtin-mic", "usb-mic"])
        #expect(options[0].active == true)
        #expect(options[0].detail == "Built-in Microphone")
        #expect(options[1].active == false)
        #expect(options[1].detail == "System default")
        #expect(options[2].active == false)
        #expect(options[2].detail == nil)
    }

    @Test("mic options: unknown selection is surfaced as an unavailable entry")
    func micOptionsUnknownSelection() {
        let fixture = CoordinatorFixture(devices: [builtInMic], defaultDevice: builtInMic)
        let coordinator = fixture.makeCoordinator()

        let options = coordinator.micDeviceOptions(selectedValue: "ghost-mic")

        #expect(options.first?.value == "ghost-mic")
        #expect(options.first?.detail == "Unavailable")
        #expect(options.first?.active == true)
        #expect(options.first { $0.value == "default" }?.active == false)
        #expect(options.filter { $0.active == true }.count == 1)
    }

    @Test("mic options: off selection activates nothing and adds no unavailable entry")
    func micOptionsOffSelection() {
        let fixture = CoordinatorFixture(devices: [usbMic, builtInMic], defaultDevice: builtInMic)
        let coordinator = fixture.makeCoordinator()

        let options = coordinator.micDeviceOptions(selectedValue: "off")

        #expect(options.map(\.value) == ["default", "builtin-mic", "usb-mic"])
        #expect(options.allSatisfy { $0.active == false })
        #expect(!options.contains { $0.detail == "Unavailable" })
    }

    @Test("mic options: existing device selection marks only that device active")
    func micOptionsExistingSelection() {
        let fixture = CoordinatorFixture(devices: [usbMic, builtInMic], defaultDevice: builtInMic)
        let coordinator = fixture.makeCoordinator()

        let options = coordinator.micDeviceOptions(selectedValue: "usb-mic")

        #expect(!options.contains { $0.detail == "Unavailable" })
        #expect(options.first { $0.value == "usb-mic" }?.active == true)
        #expect(options.filter { $0.active == true }.count == 1)
    }

    // MARK: System device options

    @Test("system options: auto is normalized to all")
    func systemOptionsAutoNormalizesToAll() {
        let fixture = CoordinatorFixture(processes: [zoomProcess])
        let coordinator = fixture.makeCoordinator()

        let options = coordinator.systemDeviceOptions(selectedValue: "auto")

        #expect(options.first?.value == "all")
        #expect(options.first?.label == "All System Audio")
        #expect(options.first?.active == true)
        #expect(!options.contains { $0.detail == "Unavailable" })
    }

    @Test("system options: off activates nothing and adds no unavailable entry")
    func systemOptionsOffSelection() {
        let fixture = CoordinatorFixture(processes: [zoomProcess])
        let coordinator = fixture.makeCoordinator()

        let options = coordinator.systemDeviceOptions(selectedValue: "off")

        #expect(options.map(\.value) == ["all", "pid:42"])
        #expect(options.allSatisfy { $0.active == false })
        #expect(!options.contains { $0.detail == "Unavailable" })
    }

    @Test("system options: unknown selection is surfaced as an unavailable entry")
    func systemOptionsUnknownSelection() {
        let fixture = CoordinatorFixture(processes: [zoomProcess])
        let coordinator = fixture.makeCoordinator()

        let options = coordinator.systemDeviceOptions(selectedValue: "pid:999")

        #expect(options.map(\.value) == ["all", "pid:999", "pid:42"])
        #expect(options[0].active == false)
        #expect(options[1].detail == "Unavailable")
        #expect(options[1].active == true)
        #expect(options[2].active == false)
    }

    @Test("system options: running process selection marks it active")
    func systemOptionsRunningProcessSelection() {
        let fixture = CoordinatorFixture(processes: [zoomProcess])
        let coordinator = fixture.makeCoordinator()

        let options = coordinator.systemDeviceOptions(selectedValue: "pid:42")

        #expect(!options.contains { $0.detail == "Unavailable" })
        #expect(options.first { $0.value == "pid:42" }?.active == true)
        #expect(options.first { $0.value == "all" }?.active == false)
    }

    // MARK: Resolved device selection

    @Test("device selection: cached value is trimmed")
    func deviceSelectionTrimsCachedValue() {
        let fixture = CoordinatorFixture(
            state: TranscriptStateSnapshot(lastMic: "  usb-mic  ")
        )
        let coordinator = fixture.makeCoordinator()

        #expect(coordinator.resolvedTranscriptDeviceSelection(for: .mic) == "usb-mic")
    }

    @Test("device selection: blank state and config fall back to default/all")
    func deviceSelectionFallsBackWhenUnset() {
        let fixture = CoordinatorFixture(
            config: TranscriptConfig(devices: TranscriptDeviceConfig(mic: "   ", system: ""))
        )
        let coordinator = fixture.makeCoordinator()

        #expect(coordinator.resolvedTranscriptDeviceSelection(for: .mic) == "default")
        #expect(coordinator.resolvedTranscriptDeviceSelection(for: .system) == "all")
    }

    @Test("device selection: cached system source wins over config")
    func deviceSelectionPrefersCachedSystemSource() {
        let fixture = CoordinatorFixture(
            config: TranscriptConfig(devices: TranscriptDeviceConfig(mic: "default", system: "all")),
            state: TranscriptStateSnapshot(lastSystemSource: "pid:7")
        )
        let coordinator = fixture.makeCoordinator()

        #expect(coordinator.resolvedTranscriptDeviceSelection(for: .system) == "pid:7")
    }

    // MARK: Model state

    @Test("model state: default model is sent when no model is configured")
    func modelStateSendsDefaultModel() {
        let fixture = CoordinatorFixture(config: TranscriptConfig(language: "ja"))
        let coordinator = fixture.makeCoordinator()

        coordinator.transcriptModelRequest(TranscriptModelRequestMessage(range: testRange))

        #expect(fixture.sink.modelStates.count == 1)
        guard let message = fixture.sink.modelStates.first else { return }
        #expect(message.range == testRange)
        #expect(message.selectedValue == SherpaOnnxModelStore.defaultModelIdentifier)
        #expect(message.modelLabel == "SenseVoice")
        #expect(message.models.map(\.value) == [
            SherpaOnnxModelStore.defaultModelIdentifier,
            SherpaOnnxModelStore.parakeetJapaneseModelIdentifier
        ])
        #expect(message.models[0].active == true)
        #expect(message.models[1].active == false)
        #expect(message.metadata?.kindLabel == "SenseVoice")
        #expect(message.metadata?.configuredLanguage == "ja")
        #expect(message.metadata?.installed == false)
        #expect(message.metadata?.installedSizeBytes == nil)
    }

    @Test("model select: unsupported identifier is ignored and current state resent")
    func modelSelectIgnoresUnsupportedIdentifier() {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.makeCoordinator()

        coordinator.transcriptModelSelect(
            TranscriptModelSelectionMessage(range: testRange, value: "unsupported-id")
        )

        #expect(fixture.selectedModels.isEmpty)
        #expect(fixture.sink.modelStates.count == 1)
        #expect(fixture.sink.modelStates.last?.selectedValue == SherpaOnnxModelStore.defaultModelIdentifier)
    }

    @Test("model select: catalog identifier is persisted and resent as selected")
    func modelSelectPersistsCatalogIdentifier() {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.makeCoordinator()

        coordinator.transcriptModelSelect(
            TranscriptModelSelectionMessage(
                range: testRange,
                value: SherpaOnnxModelStore.parakeetJapaneseModelIdentifier
            )
        )

        #expect(fixture.selectedModels == [SherpaOnnxModelStore.parakeetJapaneseModelIdentifier])
        #expect(fixture.sink.modelStates.count == 1)
        #expect(fixture.sink.modelStates.last?.selectedValue == SherpaOnnxModelStore.parakeetJapaneseModelIdentifier)
        #expect(fixture.sink.modelStates.last?.modelLabel == "Parakeet Japanese")
    }

    @Test("model state: unknown configured model falls back to the default model")
    func modelStateFallsBackForUnknownConfiguredModel() {
        let fixture = CoordinatorFixture(
            state: TranscriptStateSnapshot(transcriptModel: "no-such-model")
        )
        let coordinator = fixture.makeCoordinator()

        coordinator.sendTranscriptModelState(for: testRange)

        #expect(fixture.sink.modelStates.count == 1)
        #expect(fixture.sink.modelStates.last?.selectedValue == SherpaOnnxModelStore.defaultModelIdentifier)
        #expect(fixture.sink.modelStates.last?.modelLabel == "SenseVoice")
    }

    // MARK: Device resolution

    @Test("resolveDevices: block-selected device resolves to its unique id")
    func resolveDevicesBlockSelectedDevice() {
        let fixture = CoordinatorFixture(
            devices: [usbMic],
            defaultDevice: builtInMic,
            processes: [zoomProcess]
        )
        let coordinator = fixture.makeCoordinator()

        let resolved = coordinator.resolveDevices(
            micSelection: TranscriptDeviceSnapshot(value: "usb-mic", label: "USB Microphone"),
            systemSelection: TranscriptDeviceSnapshot(value: "all", label: "All System Audio")
        )

        #expect(resolved.micUniqueID == "usb-mic")
        #expect(resolved.micEnabled == true)
        #expect(resolved.mic.label == "USB Microphone")
        #expect(resolved.system.processes == [zoomProcess])
    }

    @Test("resolveDevices: off disables the mic")
    func resolveDevicesOffDisablesMic() {
        let fixture = CoordinatorFixture(devices: [usbMic], defaultDevice: builtInMic)
        let coordinator = fixture.makeCoordinator()

        let resolved = coordinator.resolveDevices(
            micSelection: TranscriptDeviceSnapshot(value: "off", label: "Off"),
            systemSelection: TranscriptDeviceSnapshot(value: "off", label: "Off")
        )

        #expect(resolved.micUniqueID == nil)
        #expect(resolved.micEnabled == false)
        #expect(resolved.mic.value == "off")
        #expect(resolved.system.processes.isEmpty)
    }

    @Test("resolveDevices: default selection keeps the system default input")
    func resolveDevicesDefaultSelection() {
        let fixture = CoordinatorFixture(devices: [usbMic], defaultDevice: builtInMic)
        let coordinator = fixture.makeCoordinator()

        let resolved = coordinator.resolveDevices(
            micSelection: TranscriptDeviceSnapshot(value: "default", label: "Default"),
            systemSelection: TranscriptDeviceSnapshot(value: "off", label: "Off")
        )

        #expect(resolved.micUniqueID == nil)
        #expect(resolved.micEnabled == true)
        #expect(resolved.mic.value == "default")
        #expect(resolved.mic.label == "Built-in Microphone")
    }

    @Test("makeSessionContext: resolved mic unique id reaches the session context")
    func makeSessionContextCarriesResolvedMicUniqueID() {
        let fixture = CoordinatorFixture(
            devices: [usbMic],
            defaultDevice: builtInMic,
            processes: [zoomProcess]
        )
        let coordinator = fixture.makeCoordinator()

        let resolved = coordinator.resolveDevices(
            micSelection: TranscriptDeviceSnapshot(value: "usb-mic", label: "USB Microphone"),
            systemSelection: TranscriptDeviceSnapshot(value: "all", label: "All System Audio")
        )
        let context = coordinator.makeSessionContext(for: testRange, devices: resolved)

        #expect(context.range == testRange)
        #expect(context.micDeviceUniqueID == "usb-mic")
        #expect(context.micEnabled == true)
        #expect(context.micDeviceLabel == "USB Microphone")
        #expect(context.systemDeviceLabel == "All System Audio")
        #expect(context.modelLabel == "SenseVoice")
        #expect(context.labels == fixture.config.labels)
    }
}
