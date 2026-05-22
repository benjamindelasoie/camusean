# Camusean Design System

A taste-driven, indie iOS design language. Warm amber on book paper, serif on system,
organic motion. The app exists to disappear so the book stays the product.

This file is the source of truth. When in doubt, defer to what's documented here. When
adding something not yet documented, add it here in the same PR.

## Principles

1. **The book is the product.** The app removes friction during reading; it does not
   compete for attention with the book.
2. **Reading-feel over product-feel.** Serif typography for words and headings. Warm
   earth tones, not corporate blue.
3. **One job per surface.** Each screen has one primary intent. Cards earn their
   pixels or get cut.
4. **Quiet by default.** No streaks. No celebratory animations. No notifications.
   Progress is visible but never the destination.
5. **Specific over generic.** When in doubt, pick a more concrete number, font, or
   color than the obvious default. Generic kills indie.

## Color

Single accent color. Everything else is system grayscale.

```swift
extension Color {
    // Warm amber-cognac — aged book leather, reading lamp light.
    static let camusean = Color(red: 0.74, green: 0.44, blue: 0.12)
}
```

**Accent tints** (compose with `Color.camusean.opacity(_:)`):

| Use | Opacity |
|---|---|
| icon halo, hero background tint | 0.07, 0.09, 0.11 |
| pill / chip background | 0.10, 0.12 |
| stroke separator | 0.30, 0.45, 0.65 |

**System grays** (Apple's adaptive system colors; do not hard-code):

| Token | Use |
|---|---|
| `Color(.systemBackground)` | screen background |
| `Color(.systemGray5)` | inactive fill (e.g., mic core off state) |
| `Color(.systemGray6)` | empty-state circle background, neutral pill background |
| `Color(.systemGray2)` | empty-state symbol |
| `Color(.tertiaryLabel)` | wordmark, helper captions |

**Accessibility:** `Color.camusean` on `Color(.systemBackground)` ≈ 4.6:1 contrast.
Passes WCAG AA non-large text (4.5:1) just barely. Use it for emphasis and large text
(headings, counts, accent chips); avoid for body copy on white.

## Typography

Two families: serif for the literary feel, system for everything functional.

```
Display     .system(size: 38-48, weight: .bold, design: .serif)        ← app wordmark, word display
Headline    .system(size: 22-26, weight: .semibold, design: .serif)    ← section titles, empty-state headlines
Body        .callout                                                    ← definitions, descriptions
Caption     .caption / .caption2                                        ← helper text, dates
Wordmark    .system(size: 10, weight: .bold, design: .monospaced)      ← "CAMUSEAN" header strip, kerning 2.5
```

`foregroundStyle(.secondary)` and `.tertiary` for descending visual weight on captions.

**Do NOT** use system display fonts (Inter, Roboto, SF Pro Display) for the literary
moments — `.serif` is the differentiator. The wordmark is the only monospaced touch.

## Motion

Organic, never bouncy-corporate.

```
state swap         .spring(duration: 0.35-0.45, bounce: 0.08-0.20)
fade in/out        .easeInOut(duration: 0.3-0.5)
breathing rings    .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
processing arc     .linear(duration: 1.1).repeatForever(autoreverses: false)
swipe commit       .easeIn(duration: 0.2)
```

**Reduce Motion:** all repeat-forever and spring-bounce animations MUST honor
`@Environment(\.accessibilityReduceMotion)`. When true:
- Breathing rings: static, opacity ~0.6
- Processing arc: no spin (use the dots loading view's reduced fallback)
- ZStack screen transitions: replace asymmetric scale+opacity with plain `.opacity`

## Shape

```
card / sheet content    RoundedRectangle(cornerRadius: 14-24)
pill / chip             Capsule
sheet                   presentationCornerRadius(30), presentationDetents(.medium)
```

Soft shadow on raised cards: `.shadow(color: .black.opacity(0.04-0.11), radius: 6-22, y: 2-8)`.

## Emphasis

The "halo" pattern is the signature visual moment: a soft colored circle behind an SF
Symbol, used for hero marks and empty states.

```
ZStack {
    Circle()
        .fill(Color.camusean.opacity(0.07-0.11))
        .frame(width: 100-156, height: 100-156)
    Image(systemName: "<symbol>")
        .font(.system(size: 38-52, weight: .light))
        .foregroundStyle(Color.camusean)
}
```

Variants exist with two stacked circles at different opacities for the start-screen
hero mark. Use sparingly — one halo per screen at most.

## Tabs & Navigation

3 tabs only. The trinity is sacred.

```
Read     book.fill              ReadingSessionView
Review   rectangle.stack.fill   ReviewView
Settings gearshape.fill         SettingsView
```

`TabView { ... }.tint(.camusean)`. iOS 18 `Tab(_:systemImage:)` syntax.

**Secondary destinations are pushes, not tabs.** Library is pushed from Review's nav
bar button + Review's empty-state CTA. Future "browse archive" features land the same
way. Adding a 4th tab requires a strong daily-multiple-times reason, which secondary
destinations don't have.

## Accessibility

- VoiceOver: any swipe-gesture interaction MUST have a paired
  `.accessibilityAction(named: ...)` so VoiceOver users can perform the action
  without the gesture.
- Touch targets: 44pt minimum (Apple HIG). Especially on nav-bar buttons and small icons.
- Contrast: `Color.camusean` body text on white is borderline; use for emphasis only.
- Reduce Motion: see Motion section.
- Localization-friendly: keep copy short. Word + caption rows truncate single-line on
  long French/Spanish entries — that's by design.

## Anti-Patterns (Do Not Ship)

- Generic purple/blue gradient backgrounds.
- 3-column icon-in-colored-circle feature grid.
- Centered everything.
- Cookie-cutter section rhythm (hero → 3 features → testimonials).
- Emoji as design elements.
- Streaks, daily notifications, gamification dashboards.
- A 4th tab.
- `DispatchQueue.main.asyncAfter` — use `Task.sleep` instead (Swift 6 strict
  concurrency rule; see CLAUDE.md).
- `system-ui` / default font stacks for display copy. Use `.serif`.

## Future Decisions

When extending the system:
- Adding a new color: extend `extension Color`, document the use case here.
- Adding a new motion: profile against Reduce Motion early; document curve + duration here.
- Adding a font: justify in writing why the existing serif/system pair isn't enough.

Run `/plan-design-review` on any plan that introduces UI; that skill will calibrate
new decisions against this document.
