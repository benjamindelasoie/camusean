import Foundation

// How a reader answers a flashcard, and what that means to SM-2.
//
// This mapping used to be two integer literals in `ReviewView` (q=4 on a right swipe, q=2 on a
// left one), which hid a real defect: per `SRSScheduler.easeFactorDelta`, q=4 yields exactly 0.0
// and q=2 yields −0.32, so no grade the app could produce ever RAISED an ease factor — every card
// drifted toward the 1.3 floor. Exposing `easy` (q=5) is the only way up; this type closes that seam.
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

    /// On a new or one-day card, Easy schedules identically to Good: SM-2 computes the interval
    /// from the *existing* ease factor and only then applies +0.1, so the benefit is banked for the
    /// next review rather than skipping ahead now. The label must not promise a jump it won't make.
    static let easyDoesNotSkipAhead = true
}
