import Foundation

// What a word's schedule says about how well it is known. Derived entirely from `Word`'s
// `interval`/`easeFactor`/`nextReviewDate` and never persisted — which keeps it off a schema migration.
enum WordProgress: Equatable, Sendable {
    case new
    /// Ease factor driven down near the floor — costing the most reviews for the least retention.
    case struggling
    /// Scheduled below the maturity threshold.
    case learning(days: Int)
    /// Scheduled at or beyond the maturity threshold.
    ///
    /// Deliberately NOT "mastered": one lapse resets the interval, and with no review history
    /// there is no way to say a word was ever previously mature. A statement about the current
    /// schedule, not a durable achievement — the UI label must say so.
    case mature(days: Int)

    var isMature: Bool { if case .mature = self { return true }; return false }
}

enum WordScheduleRules {
    /// The SM-2 convention for a "mature" card.
    static let matureIntervalDays = 21

    /// Sits just above `SRSScheduler`'s 1.3 floor, so it catches cards on or near it.
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
    /// "Due" means due by this instant, NOT "due before midnight" — the latter would count
    /// tomorrow-morning cards that the deck itself excludes, so the two numbers on screen would
    /// disagree. This matches the deck filter exactly, on purpose.
    static func isDue(_ word: Word, now: Date = Date()) -> Bool {
        guard let next = word.nextReviewDate else { return true }
        return next <= now
    }

    static func dueDeck(from words: [Word], now: Date = Date()) -> [Word] {
        words.filter { isDue($0, now: now) }
    }
}

/// The three numbers on the Library's stats strip. Chosen to be non-overlapping — the previous
/// set (total / due this week / learned this week) routinely rendered as "29 / 29 / 0".
struct LibraryStats: Equatable, Sendable {
    var dueNow: Int
    var learning: Int
    var mature: Int

    static func compute(for words: [Word], now: Date = Date()) -> LibraryStats {
        var dueNow = 0, learning = 0, mature = 0
        // One pass — the Library used to make three separate filter passes per render.
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
