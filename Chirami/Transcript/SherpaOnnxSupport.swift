import CSherpaOnnx
import Foundation

private func sherpaOnnxCString(_ value: String) -> UnsafePointer<CChar>? {
    (value as NSString).utf8String
}

func sherpaOnnxFeatureConfig(
    sampleRate: Int = 16_000,
    featureDim: Int = 80
) -> SherpaOnnxFeatureConfig {
    SherpaOnnxFeatureConfig(
        sample_rate: Int32(sampleRate),
        feature_dim: Int32(featureDim)
    )
}

func sherpaOnnxOfflineSenseVoiceModelConfig(
    model: String,
    language: String = "",
    useInverseTextNormalization: Bool = true
) -> SherpaOnnxOfflineSenseVoiceModelConfig {
    SherpaOnnxOfflineSenseVoiceModelConfig(
        model: sherpaOnnxCString(model),
        language: sherpaOnnxCString(language),
        use_itn: useInverseTextNormalization ? 1 : 0
    )
}

func sherpaOnnxOfflineNemoEncDecCtcModelConfig(
    model: String
) -> SherpaOnnxOfflineNemoEncDecCtcModelConfig {
    SherpaOnnxOfflineNemoEncDecCtcModelConfig(
        model: sherpaOnnxCString(model)
    )
}

func sherpaOnnxOfflineModelConfig(
    tokens: String,
    numThreads: Int = 1,
    provider: String = "cpu",
    debug: Int = 0
) -> SherpaOnnxOfflineModelConfig {
    SherpaOnnxOfflineModelConfig(
        transducer: SherpaOnnxOfflineTransducerModelConfig(),
        paraformer: SherpaOnnxOfflineParaformerModelConfig(),
        nemo_ctc: SherpaOnnxOfflineNemoEncDecCtcModelConfig(),
        whisper: SherpaOnnxOfflineWhisperModelConfig(),
        tdnn: SherpaOnnxOfflineTdnnModelConfig(),
        tokens: sherpaOnnxCString(tokens),
        num_threads: Int32(numThreads),
        debug: Int32(debug),
        provider: sherpaOnnxCString(provider),
        model_type: sherpaOnnxCString(""),
        modeling_unit: sherpaOnnxCString("cjkchar"),
        bpe_vocab: sherpaOnnxCString(""),
        telespeech_ctc: sherpaOnnxCString(""),
        sense_voice: SherpaOnnxOfflineSenseVoiceModelConfig(),
        moonshine: SherpaOnnxOfflineMoonshineModelConfig(),
        fire_red_asr: SherpaOnnxOfflineFireRedAsrModelConfig(),
        dolphin: SherpaOnnxOfflineDolphinModelConfig(),
        zipformer_ctc: SherpaOnnxOfflineZipformerCtcModelConfig(),
        canary: SherpaOnnxOfflineCanaryModelConfig(),
        wenet_ctc: SherpaOnnxOfflineWenetCtcModelConfig(),
        omnilingual: SherpaOnnxOfflineOmnilingualAsrCtcModelConfig()
    )
}

func sherpaOnnxOfflineRecognizerConfig(
    featConfig: SherpaOnnxFeatureConfig,
    modelConfig: SherpaOnnxOfflineModelConfig,
    decodingMethod: String = "greedy_search",
    maxActivePaths: Int = 4
) -> SherpaOnnxOfflineRecognizerConfig {
    SherpaOnnxOfflineRecognizerConfig(
        feat_config: featConfig,
        model_config: modelConfig,
        lm_config: SherpaOnnxOfflineLMConfig(),
        decoding_method: sherpaOnnxCString(decodingMethod),
        max_active_paths: Int32(maxActivePaths),
        hotwords_file: sherpaOnnxCString(""),
        hotwords_score: 1.5,
        rule_fsts: sherpaOnnxCString(""),
        rule_fars: sherpaOnnxCString(""),
        blank_penalty: 0,
        hr: SherpaOnnxHomophoneReplacerConfig()
    )
}

struct SherpaOnnxOfflineSegment: Equatable {
    var start: TimeInterval
    var duration: TimeInterval
    var text: String
}

final class SherpaOnnxOfflineRecognitionResult {
    private let result: UnsafePointer<SherpaOnnxOfflineRecognizerResult>

    init(result: UnsafePointer<SherpaOnnxOfflineRecognizerResult>) {
        self.result = result
    }

    deinit {
        SherpaOnnxDestroyOfflineRecognizerResult(result)
    }

    var text: String {
        guard let value = result.pointee.text else {
            return ""
        }
        return String(cString: value)
    }

    var language: String {
        guard let value = result.pointee.lang else {
            return ""
        }
        return String(cString: value)
    }

    var segments: [SherpaOnnxOfflineSegment] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let timestamps: [Float]
        if let pointer = result.pointee.timestamps {
            timestamps = (0 ..< Int(result.pointee.count)).map { pointer[$0] }
        } else {
            timestamps = []
        }

        let durations: [Float]
        if let pointer = result.pointee.durations {
            durations = (0 ..< Int(result.pointee.count)).map { pointer[$0] }
        } else {
            durations = []
        }

        let start = timestamps.first.map(TimeInterval.init) ?? 0
        let end: TimeInterval
        if let lastTimestamp = timestamps.last {
            let lastDuration = durations.last ?? 0
            end = TimeInterval(lastTimestamp + lastDuration)
        } else {
            end = 0
        }

        return [
            SherpaOnnxOfflineSegment(
                start: start,
                duration: max(0, end - start),
                text: trimmed
            )
        ]
    }
}

enum SherpaOnnxOfflineRecognizerError: LocalizedError, Equatable {
    case failedToCreateRecognizer
    case failedToCreateStream
    case failedToGetResult

    var errorDescription: String? {
        switch self {
        case .failedToCreateRecognizer:
            return "Failed to create SherpaOnnx offline recognizer."
        case .failedToCreateStream:
            return "Failed to create SherpaOnnx offline stream."
        case .failedToGetResult:
            return "Failed to read SherpaOnnx recognition result."
        }
    }
}

final class SherpaOnnxOfflineRecognizerWrapper: @unchecked Sendable {
    private let recognizer: OpaquePointer

    init(config: inout SherpaOnnxOfflineRecognizerConfig) throws {
        guard let recognizer = SherpaOnnxCreateOfflineRecognizer(&config) else {
            throw SherpaOnnxOfflineRecognizerError.failedToCreateRecognizer
        }
        self.recognizer = recognizer
    }

    deinit {
        SherpaOnnxDestroyOfflineRecognizer(recognizer)
    }

    func decode(samples: [Float], sampleRate: Int = 16_000) throws -> SherpaOnnxOfflineRecognitionResult {
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
            throw SherpaOnnxOfflineRecognizerError.failedToCreateStream
        }
        defer {
            SherpaOnnxDestroyOfflineStream(stream)
        }

        SherpaOnnxAcceptWaveformOffline(stream, Int32(sampleRate), samples, Int32(samples.count))
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
            throw SherpaOnnxOfflineRecognizerError.failedToGetResult
        }
        return SherpaOnnxOfflineRecognitionResult(result: result)
    }
}
