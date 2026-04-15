import AVFoundation
import Foundation
import Testing
@testable import Chirami

@Suite("Audio level meter")
struct AudioLevelMeterTests {
    @Test("calculates normalized RMS level")
    func calculatesNormalizedRmsLevel() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)!
        buffer.frameLength = 4

        let samples: [Float] = [0, 0.5, -0.5, 1.0]
        samples.withUnsafeBufferPointer { pointer in
            guard let channelData = buffer.floatChannelData else {
                return
            }
            channelData[0].assign(from: pointer.baseAddress!, count: samples.count)
        }

        let level = AudioLevelMeter.normalizedLevel(for: buffer)
        #expect(abs(level - 0.6123724357) < 0.0001)
    }

    @Test("calculates normalized RMS level for interleaved int16 buffers")
    func calculatesNormalizedRmsLevelForInterleavedInt16() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 2,
            interleaved: true
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        buffer.frameLength = 2

        let samples: [Int16] = [16384, -16384, 32767, -32767]
        let audioBuffer = buffer.mutableAudioBufferList.pointee.mBuffers
        let sampleCount = samples.count
        let byteCount = sampleCount * MemoryLayout<Int16>.size
        samples.withUnsafeBytes { bytes in
            memcpy(audioBuffer.mData, bytes.baseAddress, byteCount)
        }
        buffer.mutableAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(byteCount)

        let level = AudioLevelMeter.normalizedLevel(for: buffer)
        #expect(level > 0.55)
    }
}
