import Foundation

// SM-2 spaced repetition scheduler. Pure function over Word state.
//
// Quality scale (SM-2 standard):
//   0..2 = lapse (forgot or barely recalled) — interval resets to 1 day, EF decreases
//   3..5 = success — interval grows; EF adjusts up or down by quality
//
// Camusean swipe mapping (set in ReviewView):
//   right swipe = "Learned" → quality 4
//   left  swipe = "Repeat"  → quality 2 (lapse)
//
// Reference: Wozniak, Algorithm SM-2, https://supermemo.guru/wiki/SuperMemo_Algorithm_SM-2
struct SRSScheduler {
    static let minimumEaseFactor: Double = 1.3
    static let initialEaseFactor: Double = 2.5

    // Updates the word in place with the new SM-2 schedule.
    static func schedule(word: Word, quality: Int, now: Date = Date()) {
        let clampedQuality = max(0, min(5, quality))

        let newEaseFactor: Double
        let newInterval: Int

        if clampedQuality < 3 {
            // Lapse: reset interval, push EF down (clamped at floor).
            newInterval = 1
            newEaseFactor = max(
                minimumEaseFactor,
                word.easeFactor + easeFactorDelta(quality: clampedQuality)
            )
        } else {
            // Success: progress interval, adjust EF.
            switch word.interval {
            case 0:
                newInterval = 1
            case 1:
                newInterval = 6
            default:
                newInterval = Int((Double(word.interval) * word.easeFactor).rounded())
            }
            newEaseFactor = max(
                minimumEaseFactor,
                word.easeFactor + easeFactorDelta(quality: clampedQuality)
            )
        }

        word.interval = newInterval
        word.easeFactor = newEaseFactor
        word.nextReviewDate = Calendar.current.date(byAdding: .day, value: newInterval, to: now)
    }

    // SM-2 EF update term: 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)
    // q=5 → +0.1, q=4 → 0.0, q=3 → -0.14, q=2 → -0.32, q=1 → -0.54, q=0 → -0.80
    private static func easeFactorDelta(quality: Int) -> Double {
        let q = Double(quality)
        return 0.1 - (5.0 - q) * (0.08 + (5.0 - q) * 0.02)
    }
}
