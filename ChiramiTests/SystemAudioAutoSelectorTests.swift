import CoreAudio
import Foundation
import Testing
@testable import Chirami

@Suite("System audio auto selector")
struct SystemAudioAutoSelectorTests {
    @Test("selects the loudest running output process")
    func selectsLoudestRunningOutputProcess() {
        let quiet = makeProcess(pid: 10, bundleID: "com.example.quiet")
        let loud = makeProcess(pid: 20, bundleID: "com.example.loud")

        let selected = SystemAudioAutoSelector.selectProcess(
            from: [quiet, loud],
            levelsByPID: [quiet.pid: 0.2, loud.pid: 0.8]
        )

        #expect(selected == loud)
    }

    @Test("prefers the frontmost app when levels are tied")
    func prefersFrontmostAppWhenLevelsAreTied() {
        let zoom = makeProcess(pid: 30, bundleID: "us.zoom.xos")
        let meet = makeProcess(pid: 40, bundleID: "com.google.Chrome")

        let selected = SystemAudioAutoSelector.selectProcess(
            from: [zoom, meet],
            levelsByPID: [zoom.pid: 0.6, meet.pid: 0.6],
            frontmostBundleID: "com.google.Chrome"
        )

        #expect(selected == meet)
    }

    @Test("ignores non-output processes")
    func ignoresNonOutputProcesses() {
        let inputOnly = AudioProcessDescriptor(
            objectID: 1,
            pid: 50,
            bundleID: "com.example.input-only",
            isRunningInput: true,
            isRunningOutput: false
        )
        let output = makeProcess(pid: 60, bundleID: "com.example.output")

        let selected = SystemAudioAutoSelector.selectProcess(
            from: [inputOnly, output],
            levelsByPID: [inputOnly.pid: 1.0, output.pid: 0.1]
        )

        #expect(selected == output)
    }

    @Test("falls back deterministically when no levels are available")
    func fallsBackDeterministicallyWhenNoLevelsAreAvailable() {
        let unnamed = makeProcess(pid: 70, bundleID: nil)
        let named = makeProcess(pid: 80, bundleID: "com.example.named")

        let selected = SystemAudioAutoSelector.selectProcess(
            from: [unnamed, named],
            levelsByPID: [:]
        )

        #expect(selected == named)
    }

    private func makeProcess(pid: pid_t, bundleID: String?) -> AudioProcessDescriptor {
        AudioProcessDescriptor(
            objectID: AudioObjectID(pid),
            pid: pid,
            bundleID: bundleID,
            isRunningInput: false,
            isRunningOutput: true
        )
    }
}
