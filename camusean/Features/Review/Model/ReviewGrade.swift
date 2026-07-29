import Foundation

// How a reader answers a flashcard, and what that means to SM-2.
//
// This mapping used to be two integer literals inside `ReviewView` — `quality: 4` on a right
// swipe, `quality: 2` on a left one. That made it untestable, and it hid a real defect for
// the life of the app: per `SRSScheduler.easeFactorDelta`, q=4 yields a delta of exactly 0.0
// and q=2 yields −0.32. No grade the app could produce ever RAISED an ease factor, so every
// card drifted toward the 1.3 floor no matter how well it was known.
//
// `SRSSchedulerTests.perfectRecallRaisesEaseFactor` has always proved the scheduler handles
// q=5 correctly. Nothing proved the app ever sent one. That is the seam this type closes.
//
//   again ──▶ q=2 ──▶ lapse: interval resets to 1 day, EF −0.32
//   good  ──▶ q=4 ──▶ interval grows by EF, EF unchanged
//   easy  ──▶ q=5 ──▶ interval grows by EF, EF +0.10   ← the only way up
enum ReviewGrade: String, CaseIterable, Identifiable, Sendable {
    case again
    case good
    case easy

    var id: String { rawValue }

    /// SM-2 quality value. The full scale is 0...5; these are the three the UI exposes.
    var quality: Int {
        switch self {
        case .again: return 2
        case .good:  return 4
        case .easy:  return 5
        }
    }

    var label: String {
        switch self {
        case .again: return "Again"
        case .good:  return "Good"
        case .easy:  return "Easy"
        }
    }

    var systemImage: String {
        switch self {
        case .again: return "arrow.clockwise"
        case .good:  return "checkmark"
        case .easy:  return "checkmark.circle.fill"
        }
    }

    /// True when this grade counts as a lapse (SM-2 treats quality < 3 as forgotten).
    var isLapse: Bool { quality < 3 }

    /// Note for the UI: on a new or one-day card, Easy schedules identically to Good.
    /// SM-2 computes this interval from the *existing* ease factor and only then applies the
    /// +0.1, so the benefit is banked for the next review rather than skipping ahead now.
    /// The label must not promise a jump the algorithm does not make.
    static let easyDoesNotSkipAhead = true
}
