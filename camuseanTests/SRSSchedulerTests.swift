import Foundation
import Testing
@testable import camusean

@Suite struct SRSSchedulerTests {

    // Helper: build a fresh Word at defaults (interval=0, EF=2.5, nrd=nil).
    private func newWord() -> Word {
        Word(word: "flâner", sourceLanguage: "fr-FR", targetLanguage: "en-US")
    }

    // 1. First review, quality=4 → interval=1, EF unchanged (q=4 delta is exactly 0).
    @Test func firstReviewSuccessSetsIntervalToOne() {
        let word = newWord()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        SRSScheduler.schedule(word: word, quality: 4, now: now)
        #expect(word.interval == 1)
        #expect(abs(word.easeFactor - 2.5) < 0.0001)
        #expect(word.nextReviewDate != nil)
    }

    // 2. First review, quality=2 (lapse on a new word) → interval still 1, EF decreased below 2.5.
    @Test func firstReviewLapseAlsoSetsIntervalToOneAndLowersEF() {
        let word = newWord()
        SRSScheduler.schedule(word: word, quality: 2, now: Date())
        #expect(word.interval == 1)
        #expect(word.easeFactor < 2.5)
        #expect(word.easeFactor >= SRSScheduler.minimumEaseFactor)
    }

    // 3. Second successful review (prior interval=1) → interval jumps to 6 per SM-2.
    @Test func secondSuccessfulReviewSetsIntervalToSix() {
        let word = newWord()
        word.interval = 1
        word.easeFactor = 2.5
        SRSScheduler.schedule(word: word, quality: 4)
        #expect(word.interval == 6)
    }

    // 4. Third successful review (prior interval=6, EF=2.5) → interval = round(6 * 2.5) = 15.
    @Test func thirdSuccessfulReviewMultipliesByEaseFactor() {
        let word = newWord()
        word.interval = 6
        word.easeFactor = 2.5
        SRSScheduler.schedule(word: word, quality: 4)
        #expect(word.interval == 15)
    }

    // 5. Lapse from established state (interval=15) → interval resets to 1, EF decreases.
    @Test func lapseFromEstablishedStateResetsInterval() {
        let word = newWord()
        word.interval = 15
        word.easeFactor = 2.5
        SRSScheduler.schedule(word: word, quality: 2)
        #expect(word.interval == 1)
        #expect(word.easeFactor < 2.5)
        #expect(word.easeFactor >= SRSScheduler.minimumEaseFactor)
    }

    // 6. EF floor: starting EF=1.4, quality=0 (max penalty) → EF clamped at minimum 1.3.
    @Test func easeFactorClampsAtMinimum() {
        let word = newWord()
        word.easeFactor = 1.4
        SRSScheduler.schedule(word: word, quality: 0)
        #expect(abs(word.easeFactor - SRSScheduler.minimumEaseFactor) < 0.0001)
    }

    // 7. EF boost on quality=5 (perfect recall) → EF rises by 0.1.
    @Test func perfectRecallRaisesEaseFactor() {
        let word = newWord()
        word.easeFactor = 2.5
        SRSScheduler.schedule(word: word, quality: 5)
        #expect(abs(word.easeFactor - 2.6) < 0.0001)
    }

    // 8. nextReviewDate is exactly Calendar.date(byAdding: .day, value: interval, to: now).
    @Test func nextReviewDateMatchesIntervalDays() {
        let word = newWord()
        word.interval = 6
        word.easeFactor = 2.5
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        SRSScheduler.schedule(word: word, quality: 4, now: now)
        let expected = Calendar.current.date(byAdding: .day, value: word.interval, to: now)
        #expect(word.nextReviewDate == expected)
    }
}
