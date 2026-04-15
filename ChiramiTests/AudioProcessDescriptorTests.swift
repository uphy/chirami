import CoreAudio
import Testing
@testable import Chirami

@Suite("AudioProcessDescriptor")
struct AudioProcessDescriptorTests {
    @Test("transcript value stays unique per process")
    func transcriptValueUsesPID() {
        let first = AudioProcessDescriptor(
            objectID: AudioObjectID(1),
            pid: pid_t(101),
            bundleID: "company.thebrowser",
            applicationName: "Browser",
            isRunningInput: false,
            isRunningOutput: true
        )
        let second = AudioProcessDescriptor(
            objectID: AudioObjectID(2),
            pid: pid_t(202),
            bundleID: "company.thebrowser",
            applicationName: "Browser",
            isRunningInput: false,
            isRunningOutput: true
        )

        #expect(first.transcriptValue == "pid:101")
        #expect(second.transcriptValue == "pid:202")
        #expect(first.transcriptValue != second.transcriptValue)
    }
}
