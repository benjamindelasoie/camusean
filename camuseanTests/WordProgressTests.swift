import Testing
import Foundation
@testable import camusean

// Card state and the Library's stats strip. Pure derivations over fields already on `Word`,
// which is what keeps this feature off a schema migration.
@Suite("Word progress and library stats")
struct WordProgressTests {

    private func word(
        _ text: String = "fenêtre",
        definition: String = "window",
        interval: Int = 0,
        easeFactor: Double = 2.5,
        nextReview: Date? = nil,
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Word {
        let w = Word(
            word: text, definition: definition, exampleSentence: "",
            sourceLanguage: "French", targetLanguage: "English"
        )
        w.interval = interval
        w.easeFactor = easeFactor
        w.nextReviewDate = nextReview
        w.timestamp = timestamp
        return w
    }

    // MARK: - Progress classification

    @Test func neverScheduledIsNew() {
        #expect(WordScheduleRules.progress(interval: 0, easeFactor: 2.5, isScheduled: false) == .new)
    }

    @Test func maturityBoundaryIsExact() {
        // 21 days is the SM-2 maturity convention. Test the boundary, not just either side.
        #expect(WordScheduleRules.progress(interval: 20, easeFactor: 2.5, isScheduled: true) == .learning(days: 20))
        #expect(WordScheduleRules.progress(interval: 21, easeFactor: 2.5, isScheduled: true) == .mature(days: 21))
    }

    @Test func easeFactorAtTheFloorReadsAsStruggling() {
        #expect(WordScheduleRules.progress(interval: 3, easeFactor: SRSScheduler.minimumEaseFactor, isScheduled: true) == .struggling)
    }

    @Test func strugglingBeatsMaturity() {
        // A long interval with a floored ease factor is not a success story.
        #expect(WordScheduleRules.progress(interval: 60, easeFactor: 1.3, isScheduled: true) == .struggling)
    }

    // MARK: - Due logic

    @Test func neverScheduledIsDue() {
        #expect(WordScheduleRules.isDue(word(), now: Date()))
    }

    @Test func dueMeansByThisInstantNotByMidnight() {
        // Deliberate: "due now" matches the deck filter exactly. A word scheduled for later
        // today is NOT counted, because the deck will not show it either.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let laterToday = now.addingTimeInterval(3600)
        let earlier = now.addingTimeInterval(-3600)
        #expect(!WordScheduleRules.isDue(word(nextReview: laterToday), now: now))
        #expect(WordScheduleRules.isDue(word(nextReview: earlier), now: now))
        #expect(WordScheduleRules.isDue(word(nextReview: now), now: now))
    }

    @Test func deckContainsOnlyDueWords() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let deck = WordScheduleRules.dueDeck(
            from: [
                word("a", nextReview: nil),
                word("b", nextReview: now.addingTimeInterval(-1)),
                word("c", nextReview: now.addingTimeInterval(86_400)),
            ],
            now: now
        )
        #expect(deck.map(\.word) == ["a", "b"])
    }

    // MARK: - Stats

    @Test func statsAreNonOverlapping() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let stats = LibraryStats.compute(
            for: [
                word("new1"),
                word("new2"),
                word("learning", interval: 5, nextReview: now.addingTimeInterval(86_400)),
                word("mature", interval: 40, nextReview: now.addingTimeInterval(86_400)),
                word("overdue", interval: 30, nextReview: now.addingTimeInterval(-86_400)),
            ],
            now: now
        )
        #expect(stats.dueNow == 3)      // two new + one overdue
        #expect(stats.learning == 1)
        #expect(stats.mature == 2)      // the scheduled one and the overdue one
    }

    @Test func statsOnAnEmptyLibraryAreAllZero() {
        let stats = LibraryStats.compute(for: [], now: Date())
        #expect(stats == LibraryStats(dueNow: 0, learning: 0, mature: 0))
    }

    @Test func allNewLibraryHasNoLearningOrMature() {
        let stats = LibraryStats.compute(for: [word("a"), word("b")], now: Date())
        #expect(stats.dueNow == 2)
        #expect(stats.learning == 0)
        #expect(stats.mature == 0)
    }
}
