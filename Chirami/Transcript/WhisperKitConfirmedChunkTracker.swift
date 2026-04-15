import Foundation
import WhisperKit

struct WhisperKitConfirmedChunkTracker {
    private static let emissionOverlapToleranceMillis = 150
    private static let retainedConfirmedTailLength = 256

    private struct SegmentIdentity: Hashable {
        var id: Int
        var seek: Int
        var startMillis: Int
        var endMillis: Int
        var text: String
    }

    private var emittedSegmentsBySource: [TranscriptSource: Set<SegmentIdentity>] = [:]
    private var latestConfirmedEndMillisBySource: [TranscriptSource: Int] = [:]
    private var confirmedTextTailBySource: [TranscriptSource: String] = [:]

    mutating func normalize(
        confirmedSegments: [TranscriptionSegment],
        source: TranscriptSource,
        timestampOffset: TimeInterval = 0
    ) -> [TranscriptChunk] {
        var emitted = emittedSegmentsBySource[source, default: []]
        var chunks: [TranscriptChunk] = []
        let offset = Float(timestampOffset)
        var latestConfirmedEndMillis = latestConfirmedEndMillisBySource[source] ?? .min
        var confirmedTextTail = confirmedTextTailBySource[source] ?? ""

        for segment in confirmedSegments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }

            let startMillis = Int(((segment.start + offset) * 1_000).rounded())
            let endMillis = Int(((segment.end + offset) * 1_000).rounded())
            let exactIdentity = SegmentIdentity(
                id: segment.id,
                seek: segment.seek,
                startMillis: startMillis,
                endMillis: endMillis,
                text: text
            )
            guard emitted.insert(exactIdentity).inserted else {
                continue
            }

            let novelText = deduplicate(text: text, against: confirmedTextTail)
            let hasNovelTiming = endMillis > latestConfirmedEndMillis + Self.emissionOverlapToleranceMillis
            guard hasNovelTiming || !novelText.isEmpty else {
                continue
            }
            let emittedText = novelText.isEmpty ? text : novelText

            chunks.append(
                TranscriptChunk(
                    source: source,
                    timestamp: max(
                        TimeInterval(segment.start) + timestampOffset,
                        TimeInterval(max(0, latestConfirmedEndMillis)) / 1_000
                    ),
                    text: emittedText
                )
            )
            latestConfirmedEndMillis = max(latestConfirmedEndMillis, endMillis)
            confirmedTextTail = updateTail(confirmedTextTail, appending: emittedText)
        }

        emittedSegmentsBySource[source] = emitted
        latestConfirmedEndMillisBySource[source] = latestConfirmedEndMillis
        confirmedTextTailBySource[source] = confirmedTextTail
        return chunks
    }

    func latestConfirmedTimestamp(for source: TranscriptSource) -> TimeInterval? {
        guard let millis = latestConfirmedEndMillisBySource[source], millis != .min else {
            return nil
        }
        return TimeInterval(millis) / 1_000
    }

    func novelText(for source: TranscriptSource, candidateText: String) -> String? {
        let trimmed = candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let deduplicated = deduplicate(text: trimmed, against: confirmedTextTailBySource[source] ?? "")
        return deduplicated.isEmpty ? nil : deduplicated
    }

    private func deduplicate(text: String, against tail: String) -> String {
        guard !tail.isEmpty else {
            return text
        }

        let textCharacters = Array(text)
        let tailCharacters = Array(tail)
        let maxOverlap = min(textCharacters.count, tailCharacters.count)

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            let tailSuffix = tailCharacters.suffix(overlap)
            let textPrefix = textCharacters.prefix(overlap)
            if Array(tailSuffix) == Array(textPrefix) {
                let novel = String(textCharacters.dropFirst(overlap)).trimmingCharacters(in: .whitespacesAndNewlines)
                return novel
            }
        }

        return text
    }

    private func updateTail(_ existingTail: String, appending text: String) -> String {
        let combined = existingTail.isEmpty ? text : "\(existingTail)\n\(text)"
        let characters = Array(combined)
        guard characters.count > Self.retainedConfirmedTailLength else {
            return combined
        }
        return String(characters.suffix(Self.retainedConfirmedTailLength))
    }
}
