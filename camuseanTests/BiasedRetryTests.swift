import Foundation
import Testing
@testable import camusean

@Suite struct BiasedRetryTests {

    @Test func blocksRecentlyRejectedCandidate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recentlyRejected = [(transcription: "Y", at: now)]
        let filtered = SessionViewModel.filterCandidates(
            ["Y", "Z", "W"],
            rejecting: recentlyRejected,
            window: 10,
            cap: 3,
            now: now
        )
        #expect(filtered == ["Z", "W"])
    }

    @Test func ttlExpiryReadmitsCandidates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let staleAt = now.addingTimeInterval(-15) // 15s ago, outside 10s window
        let recentlyRejected = [(transcription: "Y", at: staleAt)]
        let filtered = SessionViewModel.filterCandidates(
            ["Y", "Z", "W"],
            rejecting: recentlyRejected,
            window: 10,
            cap: 3,
            now: now
        )
        #expect(filtered == ["Y", "Z", "W"])
    }

    // With cap=3 and 5 in-window rejections, only the 3 most recent are active; the two oldest
    // (still in-window) should NOT filter.
    @Test func capLimitsActiveRejectionsToMostRecent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recentlyRejected: [(transcription: String, at: Date)] = [
            (transcription: "oldest1", at: now.addingTimeInterval(-9)),
            (transcription: "oldest2", at: now.addingTimeInterval(-8)),
            (transcription: "recent1", at: now.addingTimeInterval(-3)),
            (transcription: "recent2", at: now.addingTimeInterval(-2)),
            (transcription: "recent3", at: now.addingTimeInterval(-1))
        ]
        let filtered = SessionViewModel.filterCandidates(
            ["oldest1", "oldest2", "recent1", "recent2", "recent3", "fresh"],
            rejecting: recentlyRejected,
            window: 10,
            cap: 3,
            now: now
        )
        #expect(filtered == ["oldest1", "oldest2", "fresh"])
    }

    @Test func emptyCandidatesReturnsEmpty() {
        let now = Date()
        let filtered = SessionViewModel.filterCandidates(
            [],
            rejecting: [(transcription: "Y", at: now)],
            window: 10,
            cap: 3,
            now: now
        )
        #expect(filtered.isEmpty)
    }

    @Test func matchIsCaseInsensitive() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recentlyRejected = [(transcription: "Bonjour", at: now)]
        let filtered = SessionViewModel.filterCandidates(
            ["bonjour", "BONJOUR", "Salut"],
            rejecting: recentlyRejected,
            window: 10,
            cap: 3,
            now: now
        )
        #expect(filtered == ["Salut"])
    }
}
