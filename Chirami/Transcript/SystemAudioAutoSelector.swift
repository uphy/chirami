import Foundation

enum SystemAudioAutoSelector {
    static func selectProcess(
        from processes: [AudioProcessDescriptor],
        levelsByPID: [pid_t: Double],
        frontmostBundleID: String? = nil
    ) -> AudioProcessDescriptor? {
        let candidates = processes.filter(\.isRunningOutput)
        guard !candidates.isEmpty else {
            return nil
        }

        return candidates.max { lhs, rhs in
            compare(lhs, rhs, levelsByPID: levelsByPID, frontmostBundleID: frontmostBundleID)
        }
    }

    private static func compare(
        _ lhs: AudioProcessDescriptor,
        _ rhs: AudioProcessDescriptor,
        levelsByPID: [pid_t: Double],
        frontmostBundleID: String?
    ) -> Bool {
        let lhsLevel = normalizedLevel(for: lhs, levelsByPID: levelsByPID)
        let rhsLevel = normalizedLevel(for: rhs, levelsByPID: levelsByPID)
        if lhsLevel != rhsLevel {
            return lhsLevel < rhsLevel
        }

        let lhsFrontmost = matchesFrontmost(lhs, frontmostBundleID: frontmostBundleID)
        let rhsFrontmost = matchesFrontmost(rhs, frontmostBundleID: frontmostBundleID)
        if lhsFrontmost != rhsFrontmost {
            return lhsFrontmost == false
        }

        let lhsHasBundleID = !(lhs.bundleID?.isEmpty ?? true)
        let rhsHasBundleID = !(rhs.bundleID?.isEmpty ?? true)
        if lhsHasBundleID != rhsHasBundleID {
            return lhsHasBundleID == false
        }

        let lhsLabel = lhs.displayLabel.localizedLowercase
        let rhsLabel = rhs.displayLabel.localizedLowercase
        if lhsLabel != rhsLabel {
            return lhsLabel > rhsLabel
        }

        return lhs.pid > rhs.pid
    }

    private static func normalizedLevel(
        for process: AudioProcessDescriptor,
        levelsByPID: [pid_t: Double]
    ) -> Double {
        guard let level = levelsByPID[process.pid], level.isFinite else {
            return 0
        }
        return min(1, max(0, level))
    }

    private static func matchesFrontmost(
        _ process: AudioProcessDescriptor,
        frontmostBundleID: String?
    ) -> Bool {
        guard let frontmostBundleID, !frontmostBundleID.isEmpty else {
            return false
        }
        return process.bundleID == frontmostBundleID
    }
}
