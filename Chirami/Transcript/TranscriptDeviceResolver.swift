import Foundation

struct ResolvedTranscriptSystemSelection: Equatable {
    var selection: TranscriptDeviceSnapshot
    var processes: [AudioProcessDescriptor]
}

enum TranscriptDeviceResolver {
    static func resolveMicSelection(
        blockSelection: TranscriptDeviceSnapshot,
        configuredValue: String,
        availableDevices: [AudioDeviceDescriptor],
        defaultDevice: AudioDeviceDescriptor?
    ) -> TranscriptDeviceSnapshot {
        let normalizedBlock = normalize(blockSelection.value)
        let normalizedConfigured = normalize(configuredValue)

        if normalizedBlock == "off" || normalizedConfigured == "off" {
            return TranscriptDeviceSnapshot(value: "off", label: "Off")
        }

        if let matched = findMicDevice(for: normalizedBlock, in: availableDevices) {
            return TranscriptDeviceSnapshot(value: matched.uniqueID, label: matched.name)
        }

        if let matched = findMicDevice(for: normalizedConfigured, in: availableDevices) {
            return TranscriptDeviceSnapshot(value: matched.uniqueID, label: matched.name)
        }

        return TranscriptDeviceSnapshot(
            value: "default",
            label: defaultDevice?.name ?? "Default"
        )
    }

    static func resolveSystemSelection(
        blockSelection: TranscriptDeviceSnapshot,
        configuredValue: String,
        availableProcesses: [AudioProcessDescriptor]
    ) -> ResolvedTranscriptSystemSelection {
        let normalizedBlock = normalize(blockSelection.value)
        let normalizedConfigured = normalize(configuredValue)
        let candidates = [normalizedBlock, normalizedConfigured, "all"]
            .filter { !$0.isEmpty }
            .removingDuplicates()

        for candidate in candidates {
            if candidate == "off" {
                return ResolvedTranscriptSystemSelection(
                    selection: TranscriptDeviceSnapshot(value: "off", label: "Off"),
                    processes: []
                )
            }

            if candidate == "all" {
                return ResolvedTranscriptSystemSelection(
                    selection: TranscriptDeviceSnapshot(value: "all", label: "All System Audio"),
                    processes: availableProcesses
                )
            }

            if let matched = findSystemProcess(
                for: candidate,
                labelHint: blockSelection.label,
                in: availableProcesses
            ) {
                return ResolvedTranscriptSystemSelection(
                    selection: TranscriptDeviceSnapshot(
                        value: matched.transcriptValue,
                        label: matched.displayLabel
                    ),
                    processes: groupedSystemProcesses(from: availableProcesses, matching: matched)
                )
            }
        }

        return ResolvedTranscriptSystemSelection(
            selection: TranscriptDeviceSnapshot(value: "all", label: "All System Audio"),
            processes: availableProcesses
        )
    }

    private static func findMicDevice(
        for value: String,
        in devices: [AudioDeviceDescriptor]
    ) -> AudioDeviceDescriptor? {
        guard !value.isEmpty, value != "default" else {
            return nil
        }
        return devices.first { $0.uniqueID == value || $0.name == value }
    }

    private static func findSystemProcess(
        for value: String,
        labelHint: String,
        in processes: [AudioProcessDescriptor]
    ) -> AudioProcessDescriptor? {
        if let pid = parseTranscriptProcessPID(value) {
            return processes.first(where: { $0.pid == pid })
        }

        return processes.first(where: {
            $0.transcriptValue == value ||
            $0.bundleID == value ||
            $0.displayLabel == labelHint
        })
    }

    private static func groupedSystemProcesses(
        from processes: [AudioProcessDescriptor],
        matching process: AudioProcessDescriptor
    ) -> [AudioProcessDescriptor] {
        if let bundleID = process.bundleID, !bundleID.isEmpty {
            let matches = processes.filter { $0.bundleID == bundleID }
            if !matches.isEmpty {
                return matches
            }
        }

        if let applicationName = process.applicationName, !applicationName.isEmpty {
            let matches = processes.filter { $0.applicationName == applicationName }
            if !matches.isEmpty {
                return matches
            }
        }

        return [process]
    }

    private static func parseTranscriptProcessPID(_ value: String) -> pid_t? {
        guard value.hasPrefix("pid:") else {
            return nil
        }
        guard let pid = Int32(String(value.dropFirst(4))) else {
            return nil
        }
        return pid_t(pid)
    }

    private static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "auto" ? "all" : trimmed
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
