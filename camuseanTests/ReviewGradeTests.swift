import Testing
import Foundation
@testable import camusean

// The seam that 8 green SRSSchedulerTests could not cover.
//
// `SRSSchedulerTests.perfectRecallRaisesEaseFactor` has always proved the scheduler handles
// quality 5 correctly. Nothing proved the APP ever sends a 5 — the mapping was two integer
// literals inside a view. These tests assert the mapping itself, so the defect (no grade
// could ever raise an ease factor) cannot come back.
@Suite("Review grading")
struct ReviewGradeTests {

    private func newWord() -> Word {
        Word(word: "fenêtre", definition: "window", exampleSentence: "", sourceLanguage: "French", targetLanguage: "English")
    }

    // MARK: - The mapping

    @Test func easyIsTheOnlyGradeThatCanRaiseEaseFactor() {
        // Regression guard for the original defect. If someone re-maps Easy to 4, this fails.
        let raising = ReviewGrade.allCases.filter { grade in
            let word = newWord()
            word.easeFactor = 2.5
            SRSScheduler.schedule(word: word, quality: grade.quality)
            return word.easeFactor > 2.5
        }
        #expect(raising == [.easy])
    }

    @Test func gradesMapToTheExpectedSM2Qualities() {
        #expect(ReviewGrade.again.quality == 2)
        #expect(ReviewGrade.good.quality == 4)
        #expect(ReviewGrade.easy.quality == 5)
    }

    @Test func onlyAgainIsALapse() {
        #expect(ReviewGrade.again.isLapse)
        #expect(!ReviewGrade.good.isLapse)
        #expect(!ReviewGrade.easy.isLapse)
    }

    // MARK: - End to end through the scheduler

    @Test func easyRaisesEaseFactorThroughTheMapping() {
        let word = newWord()
        word.easeFactor = 2.5
        SRSScheduler.schedule(word: word, quality: ReviewGrade.easy.quality)
        #expect(word.easeFactor > 2.5)
        #expect(abs(word.easeFactor - 2.6) < 0.0001)
    }

    @Test func goodLeavesEaseFactorUnchanged() {
        let word = newWord()
        word.easeFactor = 2.5
        SRSScheduler.schedule(word: word, quality: ReviewGrade.good.quality)
        #expect(abs(word.easeFactor - 2.5) < 0.0001)
    }

    @Test func againLapsesAndResetsInterval() {
        let word = newWord()
        word.interval = 30
        word.easeFactor = 2.5
        SRSScheduler.schedule(word: word, quality: ReviewGrade.again.quality)
        #expect(word.interval == 1)
        #expect(word.easeFactor < 2.5)
    }

    @Test func repeatedEasyGradesCompound() {
        // The behaviour the app could never reach before: a well-known word getting easier.
        let word = newWord()
        word.easeFactor = 2.5
        for _ in 0..<5 {
            SRSScheduler.schedule(word: word, quality: ReviewGrade.easy.quality)
        }
        #expect(word.easeFactor > 2.9)
    }

    @Test func easySchedulesLikeGoodOnANewCard() {
        // Documented behaviour, not a bug: SM-2 computes this interval from the EXISTING
        // ease factor and applies the +0.1 afterwards, so Easy banks its benefit for next
        // time rather than skipping ahead now. The UI label must not promise a jump.
        let easyWord = newWord()
        let goodWord = newWord()
        SRSScheduler.schedule(word: easyWord, quality: ReviewGrade.easy.quality)
        SRSScheduler.schedule(word: goodWord, quality: ReviewGrade.good.quality)
        #expect(easyWord.interval == goodWord.interval)
        #expect(easyWord.easeFactor > goodWord.easeFactor)   // the difference is banked
    }
}
