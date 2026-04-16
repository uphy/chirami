import AVFoundation
import Foundation

enum TranscriptionEngineStopMode: Sendable {
    case flushFinalChunks
    case discardPendingWork
}

protocol TranscriptionEngine: AnyObject {
    var chunks: AsyncStream<TranscriptChunk> { get }
    var previews: AsyncStream<TranscriptPreview> { get }

    func start(audioFormat: AVAudioFormat) async throws
    func feed(buffer: AVAudioPCMBuffer, source: TranscriptSource) async throws
    func stop(mode: TranscriptionEngineStopMode) async
}
