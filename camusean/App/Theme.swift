import SwiftUI
import UIKit

// The palette. Two rules hold it together:
//
//  1. A colour used as a FILL (white text on top of it) and the same colour used as TEXT
//     on the page background are different contrast problems and need different values.
//     `camusean` is the fill; `camuseanText` is the text. The fill is the brand amber at
//     full strength; the text variant is darkened in light mode so it clears WCAG AA.
//  2. Every custom colour is adaptive. A fixed RGB that looks right on white is rarely
//     right on black, and vice versa.
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

    /// The same amber as *text* on the page background. Darker in light mode (the full
    /// brand amber is only 3.82:1 on white), brighter in dark mode where the fill amber
    /// is muddy. Use for links, pills, and any amber label.
    static let camuseanText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.88, green: 0.60, blue: 0.25, alpha: 1)
            : UIColor(red: 0.67, green: 0.38, blue: 0.09, alpha: 1)
    })

    /// "Learned", "Enhanced", "Key saved". Was a fixed `Color(red: 0.18, green: 0.62,
    /// blue: 0.40)` at 6 call sites, which measured 3.38:1 on white.
    static let camuseanSuccess = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.35, green: 0.80, blue: 0.55, alpha: 1)
            : UIColor(red: 0.11, green: 0.48, blue: 0.29, alpha: 1)
    })

    /// "Repeat" on the review card. Was `systemOrange`, which is 2.20:1 on white and also
    /// collided with the brand amber sitting next to it.
    static let camuseanRepeat = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.62, blue: 0.25, alpha: 1)
            : UIColor(red: 0.72, green: 0.36, blue: 0.02, alpha: 1)
    })

    /// "Again" — the lapse. Red because that is the one colour every reader already reads
    /// as "no" without being taught, and the swipe gesture has no label to explain itself.
    ///
    /// A brick red rather than `systemRed`: the palette is aged paper and lamplight, and
    /// pure iOS red sits outside it badly. Measures 6.49:1 on white, 7.05:1 on black.
    /// Paired with `camuseanSuccess` it stays distinguishable under deuteranopia, because
    /// the two differ in lightness as well as hue — the icons carry the meaning regardless.
    static let camuseanAgain = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.42, blue: 0.36, alpha: 1)
            : UIColor(red: 0.70, green: 0.16, blue: 0.11, alpha: 1)
    })

    /// Raised surfaces — the flashcard and the cards stacked behind it.
    ///
    /// This was `Color(.systemBackground)` sitting on a page that is also
    /// `systemBackground`. In light mode a shadow separated them; in dark mode both
    /// resolve to pure black, the shadow renders against black, and the card became
    /// invisible. `secondarySystemGroupedBackground` is white in light (so the light
    /// design is unchanged) and an elevated grey in dark.
    static let camuseanCard = Color(.secondarySystemGroupedBackground)
}
