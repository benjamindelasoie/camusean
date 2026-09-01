import Foundation
import Testing
@testable import camusean

@Suite struct SRSSchedulerTests {

    // Fresh Word at defaults: interval=0, EF=2.5, nrd=nil.
    private func newWord() -> Word {
        Word(word: "flâner", sourceLanguage: "fr-FR", targetLanguage: "en-US")
    }

    // quality=4's EF delta is exactly 0, so the ease factor stays unchanged.
    @Test func firstReviewSuccessSetsIntervalToOne() {
        let word = newWord()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        SRSScheduler.schedule(word: word, quality: 4, now: now)
        #expect(word.interval == 1)
        #expect(abs(word.easeFactor - 2.5) < 0.0001)
        #expect(word.nextReviewDate != nil)
    }

    @Test func firstReviewLapseAlsoSetsIntervalToOneAndLowersEF() {
        let word = newWord()
        SRSScheduler.schedule(word: word, quality: 2, now: Date())
        #expect(word.interval == 1)
        #expect(word.easeFactor < 2.5)
        #expect(word.easeFactor >= SRSScheduler.minimumEaseFactor)
    }

    // Per SM-2, the second success (prior interval 1) jumps the interval to 6.
    @Test func secondSuccessfulReviewSetsIntervalToSix() {
        let word = newWord()
        word.interval = 1
        word.easeFactor = 2.5
        SRSScheduler.schedule(word: word, quality: 4)
        #expect(word.interval == 6)
    }

    // interval = round(6 * 2.5) = 15.
    @Test func thirdSuccessfulReviewMultipliesByEaseFactor() {
        let word = newWord()
        word.interval = 6
        word.easeFactor = 2.5
        SRSScheduler.schedule(word: word, quality: 4)
        #expect(word.interval == 15)
    }

    @Test func lapseFromEstablishedStateResetsInterval() {
        let word = newWord()
        word.interval = 15
        word.easeFactor = 2.5
        SRSScheduler.schedule(word: word, quality: 2)
        #expect(word.interval == 1)
        #expect(word.easeFactor < 2.5)
        #expect(word.easeFactor >= SRSScheduler.minimumEaseFactor)
    }

    // EF 1.4 with quality=0 (max penalty) clamps at the 1.3 floor.
    @Test func easeFactorClampsAtMinimum() {
        let word = newWord()
        word.easeFactor = 1.4
        SRSScheduler.schedule(word: word, quality: 0)
        #expect(abs(word.easeFactor - SRSScheduler.minimumEaseFactor) < 0.0001)
    }

    @Test func perfectRecallRaisesEaseFactor() {
        let word = newWord()
        word.easeFactor = 2.5
        SRSScheduler.schedule(word: word, quality: 5)
        #expect(abs(word.easeFactor - 2.6) < 0.0001)
    }

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
