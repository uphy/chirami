import AVFoundation
import Foundation

enum AudioLevelMeter {
    static func normalizedLevel(for buffer: AVAudioPCMBuffer) -> Double {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return 0
        }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else {
            return 0
        }

        if let floatChannelData = buffer.floatChannelData {
            return normalizedFloatLevel(
                channelData: floatChannelData,
                frameLength: frameLength,
                channelCount: channelCount
            )
        }

        if let int16ChannelData = buffer.int16ChannelData {
            return normalizedInt16Level(
                channelData: int16ChannelData,
                frameLength: frameLength,
                channelCount: channelCount
            )
        }

        if let int32ChannelData = buffer.int32ChannelData {
            return normalizedInt32Level(
                channelData: int32ChannelData,
                frameLength: frameLength,
                channelCount: channelCount
            )
        }

        return normalizedFromBufferList(
            buffer.audioBufferList.pointee,
            frameLength: frameLength,
            channelCount: channelCount,
            commonFormat: buffer.format.commonFormat,
            isInterleaved: buffer.format.isInterleaved
        )
    }

    private static func normalizedFloatLevel(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameLength: Int,
        channelCount: Int
    ) -> Double {
        var totalMeanSquare = 0.0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var sumSquares = 0.0
            for index in 0..<frameLength {
                let sample = Double(samples[index])
                sumSquares += sample * sample
            }
            totalMeanSquare += sumSquares / Double(frameLength)
        }

        return normalizedRMS(totalMeanSquare: totalMeanSquare, channelCount: channelCount)
    }

    private static func normalizedInt16Level(
        channelData: UnsafePointer<UnsafeMutablePointer<Int16>>,
        frameLength: Int,
        channelCount: Int
    ) -> Double {
        var totalMeanSquare = 0.0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var sumSquares = 0.0
            for index in 0..<frameLength {
                let sample = Double(samples[index]) / Double(Int16.max)
                sumSquares += sample * sample
            }
            totalMeanSquare += sumSquares / Double(frameLength)
        }

        return normalizedRMS(totalMeanSquare: totalMeanSquare, channelCount: channelCount)
    }

    private static func normalizedInt32Level(
        channelData: UnsafePointer<UnsafeMutablePointer<Int32>>,
        frameLength: Int,
        channelCount: Int
    ) -> Double {
        var totalMeanSquare = 0.0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var sumSquares = 0.0
            for index in 0..<frameLength {
                let sample = Double(samples[index]) / Double(Int32.max)
                sumSquares += sample * sample
            }
            totalMeanSquare += sumSquares / Double(frameLength)
        }

        return normalizedRMS(totalMeanSquare: totalMeanSquare, channelCount: channelCount)
    }

    private static func normalizedFromBufferList(
        _ audioBufferList: AudioBufferList,
        frameLength: Int,
        channelCount: Int,
        commonFormat: AVAudioCommonFormat,
        isInterleaved: Bool
    ) -> Double {
        guard isInterleaved else {
            return 0
        }

        let audioBuffer = audioBufferList.mBuffers
        guard let rawData = audioBuffer.mData else {
            return 0
        }

        switch commonFormat {
        case .pcmFormatFloat32:
            let samples = rawData.bindMemory(to: Float.self, capacity: frameLength * channelCount)
            return normalizedInterleavedLevel(
                samples: samples,
                frameLength: frameLength,
                channelCount: channelCount,
                scale: 1
            )
        case .pcmFormatInt16:
            let samples = rawData.bindMemory(to: Int16.self, capacity: frameLength * channelCount)
            return normalizedInterleavedLevel(
                samples: samples,
                frameLength: frameLength,
                channelCount: channelCount,
                scale: Double(Int16.max)
            )
        case .pcmFormatInt32:
            let samples = rawData.bindMemory(to: Int32.self, capacity: frameLength * channelCount)
            return normalizedInterleavedLevel(
                samples: samples,
                frameLength: frameLength,
                channelCount: channelCount,
                scale: Double(Int32.max)
            )
        default:
            return 0
        }
    }

    private static func normalizedInterleavedLevel<T: BinaryInteger>(
        samples: UnsafePointer<T>,
        frameLength: Int,
        channelCount: Int,
        scale: Double
    ) -> Double {
        var totalMeanSquare = 0.0
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let index = frame * channelCount + channel
                let sample = Double(samples[index]) / scale
                totalMeanSquare += sample * sample
            }
        }

        let sampleCount = frameLength * channelCount
        guard sampleCount > 0 else {
            return 0
        }
        return min(1.0, max(0.0, sqrt(totalMeanSquare / Double(sampleCount))))
    }

    private static func normalizedInterleavedLevel(
        samples: UnsafePointer<Float>,
        frameLength: Int,
        channelCount: Int,
        scale: Double
    ) -> Double {
        var totalMeanSquare = 0.0
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let index = frame * channelCount + channel
                let sample = Double(samples[index]) / scale
                totalMeanSquare += sample * sample
            }
        }

        let sampleCount = frameLength * channelCount
        guard sampleCount > 0 else {
            return 0
        }
        return min(1.0, max(0.0, sqrt(totalMeanSquare / Double(sampleCount))))
    }

    private static func normalizedRMS(totalMeanSquare: Double, channelCount: Int) -> Double {
        let averageMeanSquare = totalMeanSquare / Double(channelCount)
        return min(1.0, max(0.0, sqrt(averageMeanSquare)))
    }
}
