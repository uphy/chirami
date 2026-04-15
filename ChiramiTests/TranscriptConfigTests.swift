import Testing
import Yams
@testable import Chirami

@Suite("Transcript config")
struct TranscriptConfigTests {

    @Test("decodes transcript config with defaults for omitted nested keys")
    func decodesTranscriptConfigWithDefaults() throws {
        let yaml = """
        transcript:
          model: openai_whisper-small
          devices:
            mic: AirPods Pro
          labels:
            system: Room
        notes: []
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        let transcript = try #require(config.transcript)
        #expect(transcript.model == "openai_whisper-small")
        #expect(transcript.language == "auto")
        #expect(transcript.devices.mic == "AirPods Pro")
        #expect(transcript.devices.system == "auto")
        #expect(transcript.labels.mic == "You")
        #expect(transcript.labels.system == "Room")
    }

    @Test("resolved transcript defaults when section is absent")
    func resolvedTranscriptDefaultsWhenAbsent() throws {
        let yaml = """
        notes: []
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        #expect(config.transcript == nil)
        #expect(config.resolvedTranscript.model == "openai_whisper-large-v3_turbo")
        #expect(config.resolvedTranscript.language == "auto")
        #expect(config.resolvedTranscript.devices.mic == "default")
        #expect(config.resolvedTranscript.devices.system == "auto")
        #expect(config.resolvedTranscript.labels.mic == "You")
        #expect(config.resolvedTranscript.labels.system == "Others")
    }
}

@Suite("Chirami state")
struct ChiramiStateTests {

    @Test("decodes old state without transcript cache fields")
    func decodesOldStateWithoutTranscriptCacheFields() throws {
        let yaml = """
        windows:
          note-a:
            position: [100, 200]
            size: [300, 400]
            visible: true
        bookmarks: {}
        folding_states: {}
        """
        let state = try YAMLDecoder().decode(ChiramiState.self, from: yaml)
        #expect(state.lastMic == nil)
        #expect(state.lastSystemSource == nil)
        #expect(state.windows["note-a"]?.visible == true)
    }
}
