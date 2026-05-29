# TODOs — Camusean

Deferred items from past plans and reviews. Each one is something we deliberately
chose not to do in the current scope, but worth revisiting later. Whoever picks one up
should have enough context here to start without re-asking.

When you ship one, delete the entry. When you defer one, update the "When to revisit"
note.

---

## ⏱️ Reduce spoken-word → definition-spoken latency (KEY METRIC)

**What.** Cut the wall-clock time from when the reader finishes saying a word to when
they hear its meaning. This is the product's core metric — the whole value prop is
"don't break reading flow," and every extra second of dead air erodes that. Investigate
every stage of the pipeline; preprocessing, streaming, different models, caching,
parallelism — all on the table.

**The pipeline today (measure before optimizing).** Speak → `SpeechService` endpoints
the utterance → `SessionViewModel.lookup` → `AnthropicService` (Claude Haiku over
URLSession) → JSON parse → `TTSService` speaks word, then definition. Concrete suspected
contributors and levers, by stage:

1. **Silence endpointing (~1.0s fixed).** `SpeechService.restartSilenceTimer` waits a
   full second of silence before finalizing (`isFinal`). For single words that's a big,
   constant tax. Try lowering (0.5–0.7s) and/or dynamic endpointing; tradeoff is cutting
   off slow/multisyllabic speakers. Measure the false-cutoff rate before committing.
2. **ASR path: on-device vs server.** `SFSpeechRecognizer` may round-trip to Apple's
   servers unless `requiresOnDeviceRecognition = true`. On-device is faster for single
   words, removes a network hop, and works offline. Verify current behavior; test forcing
   on-device.
3. **Speak the foreign word in parallel with the network call (HIGH LEVERAGE, LOW RISK).**
   Today `SessionViewModel.lookup` speaks the word only *after* the API result returns
   (~line 164). But the transcription is known at `isFinal`, before the request fires.
   Speaking the word immediately gives instant audible feedback and hides the entire
   network+inference latency behind the word's own TTS. Strong first thing to try.
4. **Local cache of already-defined words.** The `Word` store already holds definitions.
   Check it before calling the API — repeats become instant and free.
5. **Model/network round trip (biggest variable).** Options: stream the response (SSE) and
   begin speaking the definition as the first sentence arrives instead of awaiting the full
   JSON (may require a definition-first/plain-text output format so partials are speakable);
   prompt-cache the static instruction portion of the prompt; trim `max_tokens` (currently
   256); pre-warm the HTTPS/TLS connection at session start (URLSession reuse / HTTP-2
   keep-alive) so the first lookup doesn't pay the handshake; evaluate whether a different
   fast model meaningfully wins. Haiku is already the fast tier — measure before switching.
6. **TTS first-utterance warmup.** `AVSpeechSynthesizer` has cold-start latency on its first
   utterance. Pre-warm with a silent/empty utterance at session start, or keep a warm synth.

**Where.** `camusean/Core/Services/SpeechService.swift` (endpointing, on-device flag),
`camusean/Core/Services/AnthropicService.swift` (streaming, prompt caching, max_tokens,
connection reuse), `camusean/Features/Reading/ViewModels/SessionViewModel.swift`
(parallel word TTS, cache-before-fetch), `camusean/Core/Services/TTSService.swift` (warmup).

**Do this first: instrument, don't guess.** Add timestamp logging at each boundary
(speech-final → request-sent → first-byte → parsed → TTS-start → audio-out) and capture a
real breakdown on-device. Optimize the dominant cost first. The likely top two are the 1.0s
silence timer and the network/inference round trip; #3 (parallel word TTS) probably gives the
largest *perceived* win for the least risk.

**When to revisit.** High priority — this is the metric. Worth a dedicated session once
there's a real build on hardware to measure against (post-TestFlight, or on Benja's own
device now). Pair the measurement harness with the first optimization so wins are provable.

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

## Multi-language reading: per-session switching + per-language Library

**What.** Make camusean comfortable for readers who switch languages between
sessions (some sessions in French, some in English). Two linked parts:
1. **Low-friction per-session language switch.** Today the reading language is a
   single global setting buried in Settings (`sourceLanguageLocale` /
   `sourceLanguageName`). Switching every session means a Settings detour. Surface
   a quick switch on the Reading start screen (e.g. a language chip on `startScreen`
   that the session reads from), so changing languages is one tap, not a settings trip.
2. **Per-language Library.** The Library and review deck currently mix all languages
   together. Segment/filter saved words by `Word.sourceLanguage` so a French session's
   words and an English session's words don't blur — and so review (and TTS voice) is
   scoped to one language at a time.

**Why.** The named real user (the friend) reads in both French and English. Mixed
into one undifferentiated list, the Library is confusing to review, and a French
flashcard surfacing in an English study session is wrong (different pronunciation,
different voice). The data already supports this — `Word.sourceLanguage` is stored
per row (set in `SessionViewModel.saveWord`), so this is filtering/grouping work, not
a schema change. The `ReadingLanguage` catalog (`Core/Models/ReadingLanguage.swift`)
is the natural source for the language list.

**Where.**
- Reading-language switch: `SettingsView` (global picker today) + `SessionViewModel`
  (`sourceLocale`/`sourceName` from UserDefaults) + `ReadingSessionView.startScreen`
  for the proposed quick-switch chip.
- Library: `camusean/Features/Review/Views/LibraryView.swift` — add a per-language
  filter/segment on `sourceLanguage`. Touches the same `filteredWords` as the
  [Dynamic @Query in LibraryView] TODO above — do them together.
- Review deck: `ReviewView.swift` — decide whether the SRS queue is per-language or
  offers a language scope.
- Respect the no-4th-tab preference: Library stays a push-from-Review destination,
  not a new tab.

**When to revisit.** After the friend has actually used it across both languages
(i.e., after the v1.3 TestFlight + first real feedback). Don't build multi-language
UX before confirming he reads both in practice with the app — otherwise it's another
untested-by-others guess.

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
