import Foundation

// What a word's schedule says about how well it is known.
//
// Everything here derives from fields already on `Word` — `interval`, `easeFactor`, and
// `nextReviewDate`. Nothing is persisted, which is what keeps this work off a V4→V5 schema
// migration against real device data.
enum WordProgress: Equatable, Sendable {
    /// Never scheduled. Due immediately, by definition.
    case new
    /// Scheduled, but the ease factor has been driven down near the floor. Worth attention:
    /// these are the words costing the most reviews for the least retention.
    case struggling
    /// Scheduled below the maturity threshold.
    case learning(days: Int)
    /// Currently scheduled at or beyond the maturity threshold.
    ///
    /// Deliberately NOT called "mastered". One lapse resets the interval to 1 day, and with
    /// no review history there is no way to say a word was ever previously mature. This is a
    /// statement about the current schedule, not a durable achievement, and the UI label must
    /// say so.
    case mature(days: Int)

    var isMature: Bool { if case .mature = self { return true }; return false }
}

enum WordScheduleRules {
    /// The SM-2 convention for a "mature" card. Below this a card is still being learned.
    static let matureIntervalDays = 21

    /// Ease factors at or below this are treated as struggling. `SRSScheduler` clamps at 1.3,
    /// so this catches cards sitting on or just above the floor.
    static let strugglingEaseFactor = SRSScheduler.minimumEaseFactor + 0.2

    static func progress(interval: Int, easeFactor: Double, isScheduled: Bool) -> WordProgress {
        guard isScheduled else { return .new }
        if easeFactor <= strugglingEaseFactor { return .struggling }
        if interval >= matureIntervalDays { return .mature(days: interval) }
        return .learning(days: interval)
    }

    static func progress(for word: Word, now: Date = Date()) -> WordProgress {
        progress(
            interval: word.interval,
            easeFactor: word.easeFactor,
            isScheduled: word.nextReviewDate != nil
        )
    }

    /// Whether a word is due to be reviewed.
    ///
    /// "Due" means **due by this instant**, including overdue words and never-scheduled ones.
    /// It does NOT mean "due before midnight" — that reading would put tomorrow-morning cards
    /// in today's count while the deck itself excludes them, and the two numbers would
    /// disagree on screen. This matches the deck filter exactly, on purpose.
    static func isDue(_ word: Word, now: Date = Date()) -> Bool {
        guard let next = word.nextReviewDate else { return true }
        return next <= now
    }

    /// The review deck: everything due right now, oldest first.
    static func dueDeck(from words: [Word], now: Date = Date()) -> [Word] {
        words.filter { isDue($0, now: now) }
    }
}

/// The three numbers on the Library's stats strip.
///
/// Chosen to be non-overlapping and independently meaningful. The previous set (total /
/// due this week / learned this week) routinely rendered as "29 / 29 / 0" — two identical
/// numbers and a zero.
struct LibraryStats: Equatable, Sendable {
    var dueNow: Int
    var learning: Int
    var mature: Int

    static func compute(for words: [Word], now: Date = Date()) -> LibraryStats {
        var dueNow = 0, learning = 0, mature = 0
        // One pass. The Library used to make three separate filter passes over every word,
        // recomputed on each render.
        for word in words {
            if WordScheduleRules.isDue(word, now: now) { dueNow += 1 }
            switch WordScheduleRules.progress(for: word, now: now) {
            case .mature: mature += 1
            case .learning, .struggling: learning += 1
            case .new: break
            }
        }
        return LibraryStats(dueNow: dueNow, learning: learning, mature: mature)
    }
}
