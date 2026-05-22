# TODOs — Camusean

Deferred items from past plans and reviews. Each one is something we deliberately
chose not to do in the current scope, but worth revisiting later. Whoever picks one up
should have enough context here to start without re-asking.

When you ship one, delete the entry. When you defer one, update the "When to revisit"
note.

---

## TipKit for onboarding sheets (post-v1.1)

**What.** Replace the manual `voiceOnboardingSheet` flow in `ReadingSessionView.swift`
with Apple's TipKit framework (iOS 17+).

**Why.** Currently we manage one-time onboarding via `UserDefaults.standard` flags +
`@State` + manual `.sheet` content. TipKit gives all of that for free:
- Dismissal tracking
- Eligibility rules (e.g., "show after 3rd session, max once per week")
- Frequency caps across multiple tips
- Reset for QA testing
- Localization-friendly templates

The premium-voice prompt is exactly TipKit's use case. As more onboarding moments
appear (post-first-lookup hint, "you can pull-to-refresh", etc.), TipKit scales much
better than rolling our own UserDefaults soup.

**Where.** Touch points:
- `camusean/Features/Reading/Views/ReadingSessionView.swift` — `voiceOnboardingSheet`,
  `evaluateVoiceOnboarding()`, `showVoiceOnboarding` state, `voicePromptShownKey`.
- Any future onboarding additions.

**When to revisit.** When adding the second onboarding moment. One-off was easy;
two-off is the tipping point.

---

## App Intents / Siri Shortcuts integration

**What.** Expose "Begin reading session" as an App Intent so users can say "Hey Siri,
start a camusean session" or trigger it from a shortcut/widget/lock screen action.

**Why.** Voice activation is in-genre for camusean (the whole product is voice-driven
during reading). Hands-on-book friction means the launch step is also worth removing.
Apple's App Intents framework is the official path post-iOS 16.

**Where.** New module: `camusean/Core/Intents/` (or similar). One `AppIntent`
subtype `StartReadingSessionIntent` that drives the same path as tapping "Begin
Reading" today.

**When to revisit.** After v1.1 has a few real users (your friend + 2-3 more). Don't
build a voice-activation surface before there's a habit to attach it to.

---

## Dynamic @Query in LibraryView

**What.** Replace LibraryView's computed `filteredWords` property (which runs
client-side filtering on each render) with a dynamic `@Query` whose predicate
updates when the user changes the filter/search/sort.

**Why.** Apple's recommended pattern for runtime-changing predicates is dynamic
Query (re-initialize the Query in a child view via `init`, or use `@Query` with
a `FetchDescriptor` computed from `@State`). At indie scale (<1000 words) the
current computed approach is fine. At 10k+ words the filter cost on every render
becomes noticeable.

**Where.** `camusean/Features/Review/Views/LibraryView.swift` — `filteredWords`.

**When to revisit.** If anyone's word list crosses ~5k entries. Or if you notice
list scroll lag on older devices.

---

## Graceful ModelContainer init failure recovery

**What.** Replace the `fatalError` in `camuseanApp.swift` when `ModelContainer`
fails to load with an in-app error screen that offers "reset database" as a recovery
action.

**Why.** Currently any migration failure or store corruption crashes the app on
launch with no recovery path. The user has to delete and reinstall (which we just
went through together for the v1.1 migration bug). A user-friendly error UI with
a reset button is more humane.

**Where.** `camusean/App/camuseanApp.swift` — the `sharedModelContainer` closure.
Probably extract container creation into a `ModelContainerLoader` service that
returns `Result<ModelContainer, ModelContainerError>`, then have the App body show
an error screen instead of crashing.

**When to revisit.** Before App Store submission. TestFlight users are OK with
"delete + reinstall"; paying App Store users are not.

---

## Real integration test for SwiftData lightweight migration

**What.** A test that exercises the actual V1 → V2 SwiftData lightweight migration
end-to-end: write rows under V1 schema to disk, close the container, reopen with V2
schema + MigrationPlan, assert migrated state.

**Why.** Today's `MigrationTests.swift` tests the custom `didMigrate` closure logic
directly against an in-memory V2 container. That's useful but it does NOT exercise
SwiftData's lightweight migration phase — which is exactly what broke on device in
v1.1 (the `easeFactor` "missing destination attribute" error). The test suite stayed
green while production blew up.

**Why we punted.** The straightforward integration test pattern hits
`SwiftDataError.loadIssueModelContainer` in the test harness — SwiftData seems to
keep the V1 container alive in the test process even after it goes out of scope,
which prevents reopening the same URL under V2. No clean Apple-blessed workaround
exists yet.

**Where.** `camuseanTests/MigrationTests.swift` — add a new test alongside the
existing mapping tests.

**When to revisit.** When you add the V2 → V3 migration. By then either Apple
has documented a pattern, or the workaround (separate-process test, or `xctest
--lifecycle=isolated`) will be worth the engineering cost. Until then: device
dogfooding on every schema change is the safety net.

---

## DESIGN.md adoption + drift prevention

**What.** `DESIGN.md` was added in v1.1 (extracted tokens from `Theme.swift`). Future
work should reference it instead of re-deriving tokens from code, and `/plan-design-review`
should treat DESIGN.md as the source of truth.

**Where.** Repo root `DESIGN.md`.

**When to revisit.** Whenever a PR introduces UI changes that aren't covered by the
existing tokens. Add the new token to DESIGN.md in the same PR — stale design docs
are worse than no design doc.
