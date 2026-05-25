import Foundation
import Testing
@testable import camusean

@Suite struct BiasedRetryTests {

    // 1. A candidate matching a recent rejection is filtered out; the next best survives.
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

    // 2. Rejections older than the window do NOT filter. The candidate survives.
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

    // 3. With cap=3 and 5 in-window rejections, only the most recent 3 are active.
    //    The two oldest (still in-window) should NOT filter.
    @Test func capLimitsActiveRejectionsToMostRecent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // 5 rejections, all in-window (within 10s), in chronological order.
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
        // Only the 3 most recent are active; the two oldest are dropped from the cap.
        #expect(filtered == ["oldest1", "oldest2", "fresh"])
    }

    // 4. Empty candidates list returns empty regardless of rejections.
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

    // Case-insensitive match: "Bonjour" rejected blocks "bonjour" and "BONJOUR".
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
