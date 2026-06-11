import Foundation
import os

// MARK: - TranscriptEventHandler

/// Receives decoded transcript messages from the JS bridge (JS -> Swift).
/// Implemented by TranscriptCoordinator; held weakly by NoteWebViewBridge.
///
/// All methods are required so that adding a new transcript message produces a
/// compile error on the conforming side instead of a silently missing wire.
@MainActor
protocol TranscriptEventHandler: AnyObject {
    func transcriptRecordStart(_ message: TranscriptRecordStartMessage)
    func transcriptRecordStop(_ range: TranscriptBlockRange)
    func transcriptRecordClear(_ range: TranscriptBlockRange)
    func transcriptLevelMonitorStart(_ message: TranscriptLevelMonitorStartMessage)
    func transcriptLevelMonitorStop(_ range: TranscriptBlockRange)
    func transcriptDevicesRequest(_ request: TranscriptDevicesRequestMessage)
    func transcriptDeviceSelect(_ selection: TranscriptDeviceSelectionMessage)
    func transcriptModelRequest(_ request: TranscriptModelRequestMessage)
    func transcriptModelSelect(_ selection: TranscriptModelSelectionMessage)
}

// MARK: - TranscriptMessageSink

/// Sends transcript messages into the editor WebView (Swift -> JS).
/// Implemented by NoteWebView; held weakly by TranscriptCoordinator.
@MainActor
protocol TranscriptMessageSink: AnyObject {
    func transcriptChunk(_ chunk: TranscriptChunkMessage)
    func transcriptPreviewUpdate(_ preview: TranscriptPreviewMessage)
    func transcriptStateChanged(_ state: TranscriptStateMessage)
    func transcriptLevelUpdate(_ update: TranscriptLevelUpdateMessage)
    func transcriptDevicesList(_ message: TranscriptDevicesListMessage)
    func transcriptModelState(_ message: TranscriptModelStateMessage)
    func transcriptModelDownloadProgress(_ message: TranscriptModelDownloadProgressMessage)
    func transcriptError(_ message: TranscriptErrorMessage)
}

// MARK: - Supporting types

/// Snapshot of the transcript-related fields of state.yaml.
struct TranscriptStateSnapshot: Sendable {
    var lastMic: String?
    var lastSystemSource: String?
    var transcriptModel: String?
}

/// Result of resolving block-level device selections against config and
/// currently available devices/processes.
struct ResolvedTranscriptDevices: Equatable {
    var mic: TranscriptDeviceSnapshot
    /// nil = system default input or mic off.
    var micUniqueID: String?
    var micEnabled: Bool
    var system: ResolvedTranscriptSystemSelection
}

// MARK: - TranscriptCoordinator

/// Owns the transcript domain logic for a single note window: device
/// resolution, session creation, model catalog state, and level monitor
/// lifecycle. Holds no reference to windows, panels, or SwiftUI; its only
/// outlet is `sink`.
///
/// All external dependencies (config, state, device enumeration, model store,
/// session registry) are injected through the initializer; default arguments
/// wire the production singletons.
@MainActor
final class TranscriptCoordinator: TranscriptEventHandler {
    /// Swift -> JS outlet. Weak: the WebView is owned by the SwiftUI hosting
    /// hierarchy and is recreated on periodic-note navigation. Must stay weak —
    /// a strong reference would form a retain cycle
    /// (WebView -> Bridge -> Coordinator -> WebView).
    weak var sink: TranscriptMessageSink?

    /// Active level monitors keyed by blockFrom.
    private var levelMonitors: [Int: TranscriptLevelMonitor] = [:]

    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "TranscriptCoordinator")

    // MARK: Injected dependencies

    private let transcriptConfig: () -> TranscriptConfig
    private let configDirectory: () -> URL
    private let stateSnapshot: () -> TranscriptStateSnapshot
    private let updateDeviceCache: (_ lastMic: String?, _ lastSystemSource: String?) -> Void
    private let setTranscriptModel: (String) -> Void
    private let audioInputDevices: () -> [AudioDeviceDescriptor]
    private let defaultAudioInputDevice: () -> AudioDeviceDescriptor?
    private let runningOutputProcesses: () -> [AudioProcessDescriptor]
    private let modelStore: SherpaOnnxModelStore
    private let sessionRegistry: TranscriptSessionRegistry

    init(
        transcriptConfig: @escaping () -> TranscriptConfig = { AppConfig.shared.transcriptConfig },
        configDirectory: @escaping () -> URL = { AppConfig.shared.configDirectoryURL },
        stateSnapshot: @escaping () -> TranscriptStateSnapshot = {
            let state = AppState.shared.state
            return TranscriptStateSnapshot(
                lastMic: state.lastMic,
                lastSystemSource: state.lastSystemSource,
                transcriptModel: state.transcriptModel
            )
        },
        updateDeviceCache: @escaping (_ lastMic: String?, _ lastSystemSource: String?) -> Void = {
            AppState.shared.updateTranscriptDeviceCache(lastMic: $0, lastSystemSource: $1)
        },
        setTranscriptModel: @escaping (String) -> Void = { AppState.shared.setTranscriptModel($0) },
        audioInputDevices: @escaping () -> [AudioDeviceDescriptor] = { AudioDeviceEnumerator.audioInputDevices() },
        defaultAudioInputDevice: @escaping () -> AudioDeviceDescriptor? = { AudioDeviceEnumerator.defaultAudioInputDevice() },
        runningOutputProcesses: @escaping () -> [AudioProcessDescriptor] = { AudioProcessEnumerator.runningOutputProcesses() },
        modelStore: SherpaOnnxModelStore = .shared,
        sessionRegistry: TranscriptSessionRegistry = .shared
    ) {
        self.transcriptConfig = transcriptConfig
        self.configDirectory = configDirectory
        self.stateSnapshot = stateSnapshot
        self.updateDeviceCache = updateDeviceCache
        self.setTranscriptModel = setTranscriptModel
        self.audioInputDevices = audioInputDevices
        self.defaultAudioInputDevice = defaultAudioInputDevice
        self.runningOutputProcesses = runningOutputProcesses
        self.modelStore = modelStore
        self.sessionRegistry = sessionRegistry
    }

    // MARK: - TranscriptEventHandler

    func transcriptRecordStart(_ message: TranscriptRecordStartMessage) {
        logger.info("transcriptRecordStart blockFrom=\(message.range.blockFrom) blockTo=\(message.range.blockTo)")
        let session = makeTranscriptSession(for: message)
        Task {
            await self.stopTranscriptLevelMonitor(for: message.range)
            await self.sessionRegistry.start(session)
        }
    }

    func transcriptRecordStop(_ range: TranscriptBlockRange) {
        logger.info("transcriptRecordStop blockFrom=\(range.blockFrom) blockTo=\(range.blockTo)")
        Task {
            await self.stopTranscriptLevelMonitor(for: range)
            await self.sessionRegistry.stop(range: range)
        }
    }

    func transcriptRecordClear(_ range: TranscriptBlockRange) {
        logger.info("transcriptRecordClear blockFrom=\(range.blockFrom) blockTo=\(range.blockTo)")
        Task {
            await self.stopTranscriptLevelMonitor(for: range)
            await self.sessionRegistry.clear(range: range)
        }
    }

    func transcriptLevelMonitorStart(_ message: TranscriptLevelMonitorStartMessage) {
        Task {
            await self.startTranscriptLevelMonitor(for: message)
        }
    }

    func transcriptLevelMonitorStop(_ range: TranscriptBlockRange) {
        Task {
            await self.stopTranscriptLevelMonitor(for: range)
        }
    }

    func transcriptDevicesRequest(_ request: TranscriptDevicesRequestMessage) {
        logger.debug("transcriptDevicesRequest source=\(request.source.rawValue, privacy: .public) blockFrom=\(request.range.blockFrom)")
        sendTranscriptDevicesList(for: request)
    }

    func transcriptDeviceSelect(_ selection: TranscriptDeviceSelectionMessage) {
        switch selection.source {
        case .mic:
            updateDeviceCache(selection.value, nil)
        case .system:
            updateDeviceCache(nil, selection.value)
        }
        logger.info("transcriptDeviceSelect source=\(selection.source.rawValue, privacy: .public) value=\(selection.value, privacy: .public)")
        sendTranscriptDevicesList(
            for: TranscriptDevicesRequestMessage(
                range: selection.range,
                source: selection.source
            )
        )
    }

    func transcriptModelRequest(_ request: TranscriptModelRequestMessage) {
        logger.debug("transcriptModelRequest blockFrom=\(request.range.blockFrom)")
        sendTranscriptModelState(for: request.range)
    }

    func transcriptModelSelect(_ selection: TranscriptModelSelectionMessage) {
        guard let selectedModel = try? modelStore.resolvedCatalogModel(for: selection.value) else {
            logger.warning("transcriptModelSelect ignored unsupported value=\(selection.value, privacy: .public)")
            sendTranscriptModelState(for: selection.range)
            return
        }
        setTranscriptModel(selectedModel.identifier)
        sendTranscriptModelState(for: selection.range)
    }

    // MARK: - Device resolution

    /// Resolves block-level mic/system selections against the configured
    /// values and the currently available devices/processes. Shared by
    /// session creation and level-monitor startup. Internal for tests.
    func resolveDevices(
        micSelection: TranscriptDeviceSnapshot,
        systemSelection: TranscriptDeviceSnapshot
    ) -> ResolvedTranscriptDevices {
        let config = transcriptConfig()
        let mic = TranscriptDeviceResolver.resolveMicSelection(
            blockSelection: micSelection,
            configuredValue: config.devices.mic,
            availableDevices: audioInputDevices(),
            defaultDevice: defaultAudioInputDevice()
        )
        let system = TranscriptDeviceResolver.resolveSystemSelection(
            blockSelection: systemSelection,
            configuredValue: config.devices.system,
            availableProcesses: runningOutputProcesses()
        )
        logger.debug("transcript devices resolved mic=\(mic.value, privacy: .public) system=\(system.selection.value, privacy: .public)")
        return ResolvedTranscriptDevices(
            mic: mic,
            micUniqueID: TranscriptDeviceResolver.micDeviceUniqueID(from: mic),
            micEnabled: mic.value != "off",
            system: system
        )
    }

    // MARK: - Level monitor lifecycle

    /// Stops every active level monitor. Called by the window controller on
    /// window close so MicrophoneCapture is not left running after the
    /// coordinator's owner goes away.
    func stopAllLevelMonitors() {
        let monitors = levelMonitors.values
        levelMonitors.removeAll()
        Task {
            for monitor in monitors {
                await monitor.stop()
            }
        }
    }

    private func startTranscriptLevelMonitor(for message: TranscriptLevelMonitorStartMessage) async {
        await stopTranscriptLevelMonitor(for: message.range)

        let resolved = resolveDevices(
            micSelection: message.micDevice,
            systemSelection: message.systemDevice
        )
        let monitor = TranscriptLevelMonitor(
            range: message.range,
            micEnabled: resolved.micEnabled,
            micDeviceUniqueID: resolved.micUniqueID,
            systemProcesses: resolved.system.processes
        ) { [weak self] update in
            self?.sink?.transcriptLevelUpdate(update)
        }
        levelMonitors[message.range.blockFrom] = monitor
        await monitor.start()
    }

    private func stopTranscriptLevelMonitor(for range: TranscriptBlockRange) async {
        guard let monitor = levelMonitors.removeValue(forKey: range.blockFrom) else {
            return
        }
        await monitor.stop()
    }

    // MARK: - Session creation

    /// Builds the session context from a resolved device set. Internal for
    /// tests; session creation itself stays private.
    func makeSessionContext(
        for range: TranscriptBlockRange,
        devices: ResolvedTranscriptDevices
    ) -> TranscriptSessionContext {
        TranscriptSessionContext(
            range: range,
            modelLabel: transcriptModelLabel(),
            micEnabled: devices.micEnabled,
            micDeviceLabel: devices.mic.label,
            micDeviceUniqueID: devices.micUniqueID,
            systemDeviceLabel: devices.system.selection.label,
            labels: transcriptConfig().labels
        )
    }

    private func makeTranscriptSession(for message: TranscriptRecordStartMessage) -> TranscriptSession {
        let resolved = resolveDevices(
            micSelection: message.micDevice,
            systemSelection: message.systemDevice
        )
        let resolvedPIDs = resolved.system.processes.map(\.pid).description
        logger.info(
            "transcript device resolution mic.requested=\(message.micDevice.value, privacy: .public) mic.resolved=\(resolved.mic.value, privacy: .public) system.requested=\(message.systemDevice.value, privacy: .public) system.resolved=\(resolved.system.selection.value, privacy: .public) resolvedPIDs=\(resolvedPIDs, privacy: .public)"
        )
        let callbacks = TranscriptSessionCallbacks()
        callbacks.sendChunk = { [weak self] chunk in
            self?.sink?.transcriptChunk(chunk)
        }
        callbacks.sendPreview = { [weak self] preview in
            self?.sink?.transcriptPreviewUpdate(preview)
        }
        callbacks.sendState = { [weak self] state in
            self?.sink?.transcriptStateChanged(state)
        }
        callbacks.sendLevel = { [weak self] update in
            self?.sink?.transcriptLevelUpdate(update)
        }
        callbacks.sendModelDownloadProgress = { [weak self] progress in
            self?.sink?.transcriptModelDownloadProgress(progress)
        }
        callbacks.sendError = { [weak self] error in
            self?.sink?.transcriptError(error)
        }

        let context = makeSessionContext(for: message.range, devices: resolved)

        let transcriptionEngine = makeTranscriptionEngine()
        let transcriptionEngineFactory = makeTranscriptionEngineFactory()

        return TranscriptSession(
            context: context,
            callbacks: callbacks,
            transcriptionEngine: transcriptionEngine,
            transcriptionEngineFactory: transcriptionEngineFactory,
            systemProcesses: resolved.system.processes
        )
    }

    // MARK: - Model catalog

    private struct ConfiguredTranscriptModel: Sendable {
        let identifier: String
        let label: String
        let detail: String?
        let language: String?
        let kind: SherpaOnnxModelKind
        let supportedLanguages: [String]
        let installed: Bool
        let installedSizeBytes: Int64?
    }

    private func configuredTranscriptModel() -> ConfiguredTranscriptModel? {
        let config = transcriptConfig()
        let requestedIdentifier = stateSnapshot().transcriptModel ?? defaultModelIdentifier()
        let resolvedCatalogModel =
            (try? modelStore.resolvedCatalogModel(for: requestedIdentifier)) ??
            (try? modelStore.resolvedCatalogModel(for: defaultModelIdentifier()))
        guard let resolvedCatalogModel else { return nil }

        return ConfiguredTranscriptModel(
            identifier: resolvedCatalogModel.identifier,
            label: resolvedCatalogModel.label,
            detail: resolvedCatalogModel.detail,
            language: config.language,
            kind: resolvedCatalogModel.kind,
            supportedLanguages: resolvedCatalogModel.supportedLanguages,
            installed: modelStore.modelExists(for: resolvedCatalogModel.identifier),
            installedSizeBytes: modelStore.installedSizeBytes(for: resolvedCatalogModel.identifier)
        )
    }

    private func transcriptModelKindLabel(_ kind: SherpaOnnxModelKind) -> String {
        switch kind {
        case .senseVoice:
            return "SenseVoice"
        case .nemoCTC:
            return "NeMo CTC"
        }
    }

    private func transcriptModelLabel() -> String {
        configuredTranscriptModel()?.label ?? "Configured model"
    }

    private func defaultModelIdentifier() -> String {
        SherpaOnnxModelStore.defaultModelIdentifier
    }

    /// Internal for tests.
    func sendTranscriptModelState(for range: TranscriptBlockRange) {
        guard let currentModel = configuredTranscriptModel() else { return }
        let options = modelStore.builtInModels().map { model in
            TranscriptDeviceOptionMessage(
                value: model.identifier,
                label: model.label,
                detail: model.detail,
                active: model.identifier == currentModel.identifier
            )
        }
        sink?.transcriptModelState(
            TranscriptModelStateMessage(
                range: range,
                modelLabel: currentModel.label,
                selectedValue: currentModel.identifier,
                models: options,
                metadata: TranscriptModelMetadataMessage(
                    detail: currentModel.detail,
                    kindLabel: transcriptModelKindLabel(currentModel.kind),
                    configuredLanguage: currentModel.language,
                    supportedLanguages: currentModel.supportedLanguages,
                    installed: currentModel.installed,
                    installedSizeBytes: currentModel.installedSizeBytes
                )
            )
        )
    }

    // MARK: - Transcription engine

    private func makeTranscriptionEngine() -> TranscriptionEngine? {
        guard let model = configuredTranscriptModel() else {
            return nil
        }

        guard modelStore.modelExists(for: model.identifier) else {
            logger.info("transcript sherpa engine unavailable until model exists locally: \(model.identifier, privacy: .public)")
            return nil
        }

        let modelFolder = modelStore.resolvedModelURL(for: model.identifier)
        let lexicon = configuredTranscriptLexicon()
        return SherpaOnnxEngine(
            modelFolder: modelFolder,
            modelKind: model.kind,
            language: model.language,
            hotwords: lexicon?.lexicon.hotwordsPayload
        )
    }

    private func makeTranscriptionEngineFactory() -> TranscriptTranscriptionEngineFactory? {
        guard let model = configuredTranscriptModel() else {
            return nil
        }

        guard !modelStore.modelExists(for: model.identifier) else {
            return nil
        }

        let hotwords = configuredTranscriptLexicon()?.lexicon.hotwordsPayload

        return { [logger, modelStore] progress in
            logger.info("transcript sherpa model download start: \(model.identifier, privacy: .public)")
            let modelFolder = try await modelStore.downloadModel(id: model.identifier) {
                receivedBytes,
                totalBytes,
                fractionCompleted,
                stage in
                progress(receivedBytes, totalBytes, fractionCompleted, stage)
            }
            logger.info("transcript sherpa model download finished: \(model.identifier, privacy: .public)")
            progress(0, -1, 1, .preparing)
            return SherpaOnnxEngine(
                modelFolder: modelFolder,
                modelKind: model.kind,
                language: model.language,
                hotwords: hotwords
            )
        }
    }

    private func configuredTranscriptLexicon() -> LoadedTranscriptLexicon? {
        do {
            let loaded = try loadTranscriptLexicon(
                from: transcriptConfig(),
                configDirectory: configDirectory()
            )
            if let loaded, !loaded.lexicon.sttHotwords.isEmpty {
                logger.info("transcript lexicon loaded entries=\(loaded.lexicon.sttHotwords.count) path=\(loaded.url.path, privacy: .public)")
            }
            return loaded
        } catch {
            logger.warning("transcript lexicon load failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Device list

    /// Internal for tests.
    func sendTranscriptDevicesList(for request: TranscriptDevicesRequestMessage) {
        let selectedValue = resolvedTranscriptDeviceSelection(for: request.source)
        let devices: [TranscriptDeviceOptionMessage]

        switch request.source {
        case .mic:
            devices = micDeviceOptions(selectedValue: selectedValue)
        case .system:
            devices = systemDeviceOptions(selectedValue: selectedValue)
        }

        let message = TranscriptDevicesListMessage(
            range: request.range,
            source: request.source,
            devices: devices,
            selectedValue: selectedValue
        )
        logger.info(
            "transcriptDevicesList source=\(request.source.rawValue, privacy: .public) selected=\(selectedValue, privacy: .public) count=\(devices.count)"
        )
        sink?.transcriptDevicesList(message)
    }

    /// Internal for tests.
    func resolvedTranscriptDeviceSelection(for source: TranscriptSource) -> String {
        let config = transcriptConfig()
        let state = stateSnapshot()
        let candidate: String?

        switch source {
        case .mic:
            candidate = state.lastMic ?? config.devices.mic
        case .system:
            candidate = state.lastSystemSource ?? config.devices.system
        }

        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return source == .mic ? "default" : "all"
    }

    /// Internal for tests.
    func micDeviceOptions(selectedValue: String) -> [TranscriptDeviceOptionMessage] {
        let inputDevices = audioInputDevices()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let defaultDevice = defaultAudioInputDevice()
        let deviceValues = Set(inputDevices.map(\.uniqueID))
        let normalizedSelectedValue = selectedValue == "off" ? "off" : selectedValue
        var options: [TranscriptDeviceOptionMessage] = []

        if normalizedSelectedValue != "default" &&
            normalizedSelectedValue != "off" &&
            !deviceValues.contains(normalizedSelectedValue) {
            options.append(
                TranscriptDeviceOptionMessage(
                    value: normalizedSelectedValue,
                    label: normalizedSelectedValue,
                    detail: "Unavailable",
                    active: true
                )
            )
        }

        options.append(
            TranscriptDeviceOptionMessage(
                value: "default",
                label: "Default",
                detail: defaultDevice?.name ?? "System default",
                active: normalizedSelectedValue == "default"
            )
        )

        options.append(contentsOf: inputDevices.map { device in
            TranscriptDeviceOptionMessage(
                value: device.uniqueID,
                label: device.name,
                detail: device.uniqueID == defaultDevice?.uniqueID ? "System default" : nil,
                active: device.uniqueID == normalizedSelectedValue
            )
        })

        return options
    }

    /// Internal for tests.
    func systemDeviceOptions(selectedValue: String) -> [TranscriptDeviceOptionMessage] {
        let processes = runningOutputProcesses()
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
        let processValues = Set(processes.map(\.transcriptValue))
        let normalizedSelectedValue = selectedValue == "auto" ? "all" : selectedValue
        var options: [TranscriptDeviceOptionMessage] = [
            TranscriptDeviceOptionMessage(
                value: "all",
                label: "All System Audio",
                detail: "Capture all active system audio",
                active: normalizedSelectedValue == "all"
            )
        ]

        if normalizedSelectedValue != "all" && normalizedSelectedValue != "off" && !processValues.contains(normalizedSelectedValue) {
            options.append(
                TranscriptDeviceOptionMessage(
                    value: normalizedSelectedValue,
                    label: normalizedSelectedValue,
                    detail: "Unavailable",
                    active: true
                )
            )
        }

        options.append(contentsOf: processes.map { process in
            TranscriptDeviceOptionMessage(
                value: process.transcriptValue,
                label: process.displayLabel,
                detail: process.transcriptDetail,
                active: process.transcriptValue == normalizedSelectedValue
            )
        })

        return options
    }
}
