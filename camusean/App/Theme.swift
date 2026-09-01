import SwiftUI
import UIKit

// The palette. Two rules hold it together:
//
//  1. A colour used as a FILL (white text on top) and the same colour used as TEXT on the page
//     background are different contrast problems needing different values. `camusean` is the fill
//     (brand amber, full strength); `camuseanText` is the text (darkened in light mode for WCAG AA).
//  2. Every custom colour is adaptive — a fixed RGB that reads right on white rarely reads right on black.
//
// Measured ratios (WCAG 2.1, AA needs 4.5:1 for body text, 3:1 for large text and fills):
//   white on camusean fill ....... 3.82:1  (large/semibold button labels only)
//   camuseanText on white ........ 4.72:1
//   camuseanText on black ........ 8.81:1
//   success on white ............. 5.31:1     success on black ....... 10.44:1
//   repeat on white .............. 4.61:1     repeat on black ........ 10.22:1
extension Color {
    /// Warm amber-cognac — aged book leather, reading lamp light. Fill only: button
    /// backgrounds, tints, and low-opacity washes. White text on top passes at 3:1.
    static let camusean = Color(red: 0.74, green: 0.44, blue: 0.12)

    /// The same amber as *text* on the page background. Darker in light mode (the fill amber is
    /// only 3.82:1 on white), brighter in dark mode where it is muddy. Links, pills, amber labels.
    static let camuseanText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.88, green: 0.60, blue: 0.25, alpha: 1)
            : UIColor(red: 0.67, green: 0.38, blue: 0.09, alpha: 1)
    })

    /// "Learned", "Enhanced", "Key saved". Replaced a fixed green that measured only 3.38:1 on white.
    static let camuseanSuccess = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.35, green: 0.80, blue: 0.55, alpha: 1)
            : UIColor(red: 0.11, green: 0.48, blue: 0.29, alpha: 1)
    })

    /// "Repeat" on the review card. Replaced `systemOrange` (2.20:1 on white, and it collided
    /// with the brand amber next to it).
    static let camuseanRepeat = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.62, blue: 0.25, alpha: 1)
            : UIColor(red: 0.72, green: 0.36, blue: 0.02, alpha: 1)
    })

    /// "Again" — the lapse. Red reads as "no" without teaching, and the swipe has no label.
    /// A brick red rather than `systemRed`, which sits outside the aged-paper palette (6.49:1 on
    /// white, 7.05:1 on black). Differs from `camuseanSuccess` in lightness as well as hue, so the
    /// pair stays distinguishable under deuteranopia.
    static let camuseanAgain = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.42, blue: 0.36, alpha: 1)
            : UIColor(red: 0.70, green: 0.16, blue: 0.11, alpha: 1)
    })

    /// Raised surfaces — the flashcard and the cards stacked behind it.
    ///
    /// Not `Color(.systemBackground)`: on a `systemBackground` page both resolve to pure black in
    /// dark mode, so the shadow renders against black and the card vanishes.
    /// `secondarySystemGroupedBackground` is white in light (unchanged) and an elevated grey in dark.
    static let camuseanCard = Color(.secondarySystemGroupedBackground)
}
