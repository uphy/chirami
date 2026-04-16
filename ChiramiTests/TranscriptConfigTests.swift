import Testing
import Yams
@testable import Chirami

@Suite("Transcript config")
struct TranscriptConfigTests {

    @Test("decodes transcript config with defaults for omitted nested keys")
    func decodesTranscriptConfigWithDefaults() throws {
        let yaml = """
        transcript:
          engine: sherpa-onnx
          model: sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17
          devices:
            mic: AirPods Pro
          labels:
            system: Room
        notes: []
        """
        let config = try YAMLDecoder().decode(ChiramiConfig.self, from: yaml)
        let transcript = try #require(config.transcript)
        #expect(transcript.engine == "sherpa-onnx")
        #expect(transcript.legacyModel == "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17")
        #expect(transcript.language == "auto")
        #expect(transcript.devices.mic == "AirPods Pro")
        #expect(transcript.devices.system == "all")
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
        #expect(config.resolvedTranscript.engine == "sherpa-onnx")
        #expect(config.resolvedTranscript.legacyModel == nil)
        #expect(config.resolvedTranscript.language == "auto")
        #expect(config.resolvedTranscript.devices.mic == "default")
        #expect(config.resolvedTranscript.devices.system == "all")
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
        #expect(state.transcriptModel == nil)
        #expect(state.lastMic == nil)
        #expect(state.lastSystemSource == nil)
        #expect(state.windows["note-a"]?.visible == true)
    }

    @Test("decodes transcript model state")
    func decodesTranscriptModelState() throws {
        let yaml = """
        windows: {}
        bookmarks: {}
        folding_states: {}
        transcript_model: sherpa-onnx-nemo-parakeet-tdt_ctc-0.6b-ja-35000-int8
        last_mic: Built-in Microphone
        last_system_source: all
        """
        let state = try YAMLDecoder().decode(ChiramiState.self, from: yaml)
        #expect(state.transcriptModel == "sherpa-onnx-nemo-parakeet-tdt_ctc-0.6b-ja-35000-int8")
        #expect(state.lastMic == "Built-in Microphone")
        #expect(state.lastSystemSource == "all")
    }
}
