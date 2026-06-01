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

1. **Silence endpointing.** ✅ **Partly shipped 2026-06-01** — lowered 1.0s → 0.6s via the
   named `SpeechService.silenceTimeout` constant. _Remaining:_ try 0.5s and/or dynamic
   endpointing; measure the false-cutoff rate on hardware before lowering further.
2. **ASR path: on-device vs server.** `SFSpeechRecognizer` may round-trip to Apple's
   servers unless `requiresOnDeviceRecognition = true`. On-device is faster for single
   words, removes a network hop, and works offline. Verify current behavior; test forcing
   on-device.
3. **Speak the foreign word in parallel with the network call.** ✅ **Shipped 2026-06-01** —
   `SessionViewModel.lookup` now fires the definition request as `async let pending` and
   speaks the native word echo concurrently, so the echo hides the network round-trip
   instead of stacking after it. The echo now also fires before the result is known (so a
   failed/offline lookup still echoes the word, then reports the failure).
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

---

## 📚 Frequent-word definition cache (local dictionary, "Regime A")

**What.** A local definition cache so common words resolve **instantly, offline, and
free** — no Anthropic round-trip. Lookup path becomes:

```
spoken word
  → NaturalLanguage lemmatize (on-device)        ← maps inflections to the dictionary form
  → local dictionary cache (bundled + lazy)       ← majority of lookups: instant, offline
  → [miss] Claude Haiku, prompted to match the    ← rare tail only
           dictionary's terse gloss style
```

**Why we deferred (2026-06-01).** We chose the Haiku-only path for v1. The cache only
earns its real complexity (lemmatization, dictionary parsing, frozen quality, homograph
senses, attribution, a build pipeline) once one of these is true:
- **Offline reading is a real user scenario** (subway / plane / spotty cell) — the cache
  is the *only* way to work offline; the live path can never.
- **API cost / the 200-lookup daily cap is binding** — every cache hit is an Anthropic
  call avoided, which materially extends the pre-seeded **capped key** onboarding runway.
  (Benja flagged this cost-reduction angle as a standalone reason to want it.)

Until then, prefer the cheap live-path optimizations (see the latency TODO: drop the
example from the live call / trim `max_tokens`, pre-warm the connection) and measure
whether they're "good enough on wifi" before building this.

**Design decisions already made (so we don't re-litigate):**
- **Source the cache from a dictionary, NOT from Anthropic** — regeneration must never
  call the API (explicit Benja requirement). Candidates:
  - **Kaikki.org / wiktextract** (Kaikki = the published JSON output of the wiktextract
    parser): broad coverage, multiple senses, **includes IPA**, *some* usage examples.
    License CC BY-SA (needs an attribution screen). More parsing/curation — entries are
    multi-sense and must be trimmed to one spoken-friendly gloss.
  - **FreeDict `fra-eng`** (TEI XML): terse bilingual glosses (already close to
    spoken-ready), simpler to parse, lighter license, but thinner coverage and almost
    no examples.
- **Lemmatization is mandatory**, via Apple's `NaturalLanguage` (`NLTagger` `.lemma`),
  on-device/free. Without it the cache misses most real (inflected) speech.
- **Consistency:** keep ONE voice across tiers by making the *live Haiku fallback* imitate
  the dictionary's terse style — not the other way round. Resolves the cache/live style seam
  without putting Anthropic in the regen loop.
- **Store:** hybrid — ship a bundled top-N (~5–10k, ~1–2MB, a non-issue) AND lazily write
  the user's tail lookups into the same store. Fast on day one, personalizes over time.
- **Examples are a known downgrade** vs Haiku: dictionary examples are patchy/absent.
  Accept empty examples (Review already handles them) or lazily backfill via Haiku on first
  review (reintroduces the API, just deferred).
- **Homographs** (*livre* = book/pound): cache the most-frequent sense; let the existing
  reject/retry gesture force a live, cache-bypassing lookup for the wrong-sense case.
- Cache is **per language pair** (keyed by source+target). Trivial at current 1-pair scope.

**Where.** New `DefinitionProvider` (cache-then-network) in front of `AnthropicService`;
`NaturalLanguage` lemmatizer in the lookup path; a one-time generation script (frequency
list + Kaikki/FreeDict → extraction/trim → bundled file). Frequency list from
Lexique.org or OpenSubtitles freq lists (word lists aren't copyrightable; glosses are the
dictionary's, under its license).

**When to revisit.** When offline reading proves a real use case, OR when the daily cap /
API cost starts biting onboarding — whichever comes first. Also revisit if the live-path
latency work lands and still isn't fast/consistent enough on cellular.

---

## 🔊 Speech (TTS) quality — beyond Apple's system voices

**What.** Replace or augment `AVSpeechSynthesizer` for smoother, more natural speech.
Apple's system voices — even Enhanced/Premium — aren't SOTA-smooth, and Benja noted this.

**Why (and why it becomes urgent later).** Once retrieval latency is hidden (echo overlap
shipped; cache or live-path work to come), **TTS becomes both the dominant remaining
latency AND the main perceived-quality surface** of the whole experience. The voice *is*
the product at that point.

**Options (poles):**
- **On-device neural TTS** — e.g. **Kokoro (82M, MIT)** or **Piper**, via CoreML/ONNX.
  Cloud-ish quality, **offline, free, private**, zero network latency. Cost: model
  bundling + multilingual voice setup. Best fit for Camusean's ethos; pairs naturally
  with the offline cache above (offline retrieval + offline TTS = fully offline sessions).
- **Low-latency cloud TTS** — **Cartesia Sonic** or **ElevenLabs Flash**: best naturalness,
  streams with ~75–150ms time-to-first-audio. Cost: network dependency + per-use cost +
  another key — fights the instant/offline feel. If used, apply it **only to the English
  definition**, never the foreign word.
- **Max out AVSpeech (cheapest)** — actively guide users to download the Enhanced/Premium
  voice (we already detect it via `TTSService.hasEnhancedVoice`); use
  `AVSpeechSynthesisIPANotation` for tricky foreign words (Kaikki provides IPA if we adopt
  it). Zero new deps; ceiling is still "system voice."

**Hard constraint:** whatever engine handles the English definition, keep the **foreign
word echo on a native-locale voice** — a native voice pronounces the word correctly, which
is the whole point of the echo (the "hear the correct pronunciation" feature).

**Where.** `camusean/Core/Services/TTSService.swift` (currently `AVSpeechSynthesizer` +
`bestVoice(for:)`). A new engine would slot behind the same `speak(_:language:)` interface.

**When to revisit.** After the live-path latency work lands (TTS becomes the budget), or on
the first real tester complaint about voice quality. Consider pairing with the cache TODO
for a fully-offline path.
