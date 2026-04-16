import Testing
@testable import Chirami

@Suite("Transcript device resolver")
struct TranscriptDeviceResolverTests {
    @Test("mic falls back from block default to configured device")
    func micFallsBackFromBlockDefaultToConfiguredDevice() {
        let devices = [
            AudioDeviceDescriptor(uniqueID: "built-in", name: "Built-in Microphone"),
            AudioDeviceDescriptor(uniqueID: "airpods", name: "AirPods Pro")
        ]

        let resolved = TranscriptDeviceResolver.resolveMicSelection(
            blockSelection: TranscriptDeviceSnapshot(value: "default", label: "Default"),
            configuredValue: "airpods",
            availableDevices: devices,
            defaultDevice: devices[0]
        )

        #expect(resolved.value == "airpods")
        #expect(resolved.label == "AirPods Pro")
    }

    @Test("mic falls back to system default when block and config are unavailable")
    func micFallsBackToSystemDefaultWhenOverridesAreUnavailable() {
        let devices = [
            AudioDeviceDescriptor(uniqueID: "built-in", name: "Built-in Microphone")
        ]

        let resolved = TranscriptDeviceResolver.resolveMicSelection(
            blockSelection: TranscriptDeviceSnapshot(value: "missing-device", label: "Missing"),
            configuredValue: "missing-config",
            availableDevices: devices,
            defaultDevice: devices[0]
        )

        #expect(resolved.value == "default")
        #expect(resolved.label == "Built-in Microphone")
    }

    @Test("system falls back from unavailable block selection to configured process")
    func systemFallsBackFromUnavailableBlockSelectionToConfiguredProcess() {
        let arc = AudioProcessDescriptor(
            objectID: 1,
            pid: 101,
            bundleID: "company.thebrowser.Browser",
            applicationName: "Arc",
            isRunningInput: false,
            isRunningOutput: true
        )
        let helper = AudioProcessDescriptor(
            objectID: 2,
            pid: 102,
            bundleID: "company.thebrowser.Browser",
            applicationName: "Arc",
            isRunningInput: false,
            isRunningOutput: true
        )

        let resolved = TranscriptDeviceResolver.resolveSystemSelection(
            blockSelection: TranscriptDeviceSnapshot(value: "pid:999", label: "Missing"),
            configuredValue: "pid:101",
            availableProcesses: [arc, helper]
        )

        #expect(resolved.selection.value == "pid:101")
        #expect(resolved.selection.label == "Arc")
        #expect(resolved.processes.map(\.pid) == [101, 102])
    }

    @Test("system legacy auto value is normalized to all system audio")
    func systemLegacyAutoValueIsNormalizedToAllSystemAudio() {
        let zoom = AudioProcessDescriptor(
            objectID: 1,
            pid: 201,
            bundleID: "us.zoom.xos",
            applicationName: "Zoom",
            isRunningInput: false,
            isRunningOutput: true
        )
        let arc = AudioProcessDescriptor(
            objectID: 2,
            pid: 202,
            bundleID: "company.thebrowser.Browser",
            applicationName: "Arc",
            isRunningInput: false,
            isRunningOutput: true
        )

        let resolved = TranscriptDeviceResolver.resolveSystemSelection(
            blockSelection: TranscriptDeviceSnapshot(value: "auto", label: "Auto"),
            configuredValue: "auto",
            availableProcesses: [zoom, arc]
        )

        #expect(resolved.selection.value == "all")
        #expect(resolved.selection.label == "All System Audio")
        #expect(resolved.processes.map(\.pid) == [201, 202])
    }
}
