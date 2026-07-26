import Testing
import Foundation
@testable import Chirami

@Suite("StreamFollow")
struct StreamFollowTests {

    private let latest = URL(fileURLWithPath: "/notes/claude/2026-07-13-100000.md")
    private let older = URL(fileURLWithPath: "/notes/claude/2026-07-13-090000.md")

    @Test("advances when the displayed file is the previous latest and the window is visible")
    func advancesWhenShowingLatestAndVisible() {
        let result = StreamFollow.shouldFollow(isVisible: true, displayedFile: latest, previousLatest: latest)
        #expect(result)
    }

    @Test("does not advance when an older file is displayed, even while visible")
    func doesNotAdvanceWhenShowingHistory() {
        let result = StreamFollow.shouldFollow(isVisible: true, displayedFile: older, previousLatest: latest)
        #expect(!result)
    }

    @Test("does not advance when the window is hidden, even if showing the previous latest")
    func doesNotAdvanceWhenHidden() {
        let result = StreamFollow.shouldFollow(isVisible: false, displayedFile: latest, previousLatest: latest)
        #expect(!result)
    }

    @Test("does not advance when there was no previous latest (first file in an empty directory)")
    func doesNotAdvanceWithNoPreviousLatest() {
        let result = StreamFollow.shouldFollow(isVisible: true, displayedFile: latest, previousLatest: nil)
        #expect(!result)
    }
}
