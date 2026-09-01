# Project: Camusean

Voice reading companion — say a foreign word aloud during a reading session, hear the definition instantly, review saved words as flashcards later.

## Quick Reference
- **Platform**: iOS 18+ (iOS 26+ unlocks the newer on-device speech path)
- **Language**: Swift 6 language mode (complete strict concurrency). `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app + unit-test targets — types default to `@MainActor`; the UITest target stays nonisolated (XCTest compatibility).
- **UI Framework**: SwiftUI
- **Architecture**: MVVM with `@Observable`; services injected via swift-dependencies
- **Persistence**: SwiftData (versioned schema + migration)
- **Package Manager**: Swift Package Manager. External packages: `pointfreeco/swift-dependencies` (dependency injection).
- **Bundle ID**: com.bdelasoie.camusean

## XcodeBuildMCP Integration
**IMPORTANT**: This project uses XcodeBuildMCP for all Xcode operations. It runs on **session defaults** — call `session_show_defaults` once before the first build/test; once project/scheme/simulator are set, the tools below take no args.
- Compile-check: `mcp__xcodebuildmcp__build_sim`
- Test: `mcp__xcodebuildmcp__test_sim` (to spare the machine, `xcodebuild test-without-building -only-testing:camuseanTests` runs just the unit suite, no UITests/audio)
- Clean: `mcp__xcodebuildmcp__clean`

The `.xcodeproj` is at `camusean.xcodeproj` (same directory as this file). Swift sources live one level down in `camusean/` (the `PBXFileSystemSynchronizedRootGroup`).

## Project Structure
```
camusean/                        ← repo root (you are here)
├── CLAUDE.md
├── camusean.xcodeproj/
└── camusean/                    ← Swift source root (PBXFileSystemSynchronizedRootGroup)
    ├── App/
    │   ├── camuseanApp.swift         # App entry point, ModelContainer setup
    │   └── ContentView.swift         # TabView shell (Read / Review / Settings)
    ├── Features/
    │   ├── Reading/
    │   │   ├── ViewModels/
    │   │   │   └── SessionViewModel.swift  # Session state, lookup logic, mic coordination
    │   │   └── Views/
    │   │       └── ReadingSessionView.swift # Push-to-talk UI, session lifecycle
    │   ├── Review/
    │   │   └── Views/
    │   │       └── ReviewView.swift         # Flashcard deck, swipe left=known
    │   └── Settings/
    │       └── Views/
    │           └── SettingsView.swift       # Language picker, API key entry
    └── Core/
        ├── Models/
        │   └── Word.swift                   # SwiftData model
        └── Services/
            ├── AnthropicService.swift            # Claude Haiku API calls via URLSession
            ├── AudioSessionManager.swift         # AVAudioSession lifecycle (@MainActor)
            ├── KeychainService.swift             # API key storage (Security framework)
            ├── SpeechRecognizing.swift           # `SpeechRecognizing` protocol seam + `SpeechRecognition.make()` factory + shared candidate helper
            ├── SpeechService.swift               # LegacySpeechRecognizer — SFSpeechRecognizer backend (iOS 18–25)
            ├── DictationSpeechRecognizer.swift   # iOS 26+ backend — SpeechAnalyzer + DictationTranscriber (on-device)
            ├── SpeechRecognizerDependency.swift  # swift-dependencies registration for the speech seam
            └── TTSService.swift                  # AVSpeechSynthesizer (@MainActor delegate)
```

> **Note**: Xcode auto-discovers all `.swift` files in this directory via filesystem sync — no need to manually add files to the project. Just create the file on disk and it's included.

## Architecture

### Concurrency rules
- All UI state lives in `@Observable @MainActor` classes.
- Use `async/await` everywhere. No `DispatchQueue`, no completion handlers.
- `AVAudioSession` must be called from `@MainActor` — use `AudioSessionManager.shared`.
- `TTSService` must be `@MainActor NSObject` to satisfy `AVSpeechSynthesizerDelegate` (Objective-C delegate + Swift 6 strict concurrency requirement).
- `SFSpeechRecognizer` callbacks arrive on background threads — always hop to `@MainActor` with `Task { @MainActor in ... }`.
- One sanctioned `nonisolated(unsafe)`: `AVAudioConverter`'s `@Sendable` input block must return a non-Sendable `AVAudioPCMBuffer` (`DictationSpeechRecognizer.BufferConverter`). It's an AVFoundation annotation gap, not a real race — the block runs synchronously on the same thread.

### Speech recognition (two backends behind one seam)
- All speech-to-text goes through the `SpeechRecognizing` protocol. `SpeechRecognition.make()` selects by OS: **iOS 26+ → `DictationSpeechRecognizer`** (Apple's on-device `SpeechAnalyzer` + `DictationTranscriber`), **iOS 18–25 → `LegacySpeechRecognizer`** (`SFSpeechRecognizer`).
- View models depend on the protocol, never a concrete backend. Both share the `SpeechRecognition.extractDistinctTranscriptions` candidate helper and the same 0.6s aggressive endpointing.
- `DictationTranscriber` (not `SpeechTranscriber`) is deliberate: it reuses system dictation assets — no large model download.
- **Known gap**: if `DictationTranscriber` doesn't support the source locale, `listenForCandidates()` returns `[]` (silent degrade). fr-FR + the shipped languages are all system dictation languages. A per-locale fallback to the legacy recognizer is the close-the-gap move if a user's language isn't supported.

### Dependency injection (swift-dependencies)
- Inject services via swift-dependencies; don't construct them inline. Two shapes are in use: a **protocol seam** for stateful, main-actor services (`SpeechRecognizing`), and a **closure client** — a `Sendable` struct of `@Sendable` closures — for stateless/off-main-actor calls, which sidesteps the module's MainActor-default isolation (`BookMetadataClient`, `WordLookupClient`, `APIKeyStore`, `SpeechSynthesizerClient`). Either way: a `DependencyKey` with **`nonisolated`** `liveValue`/`testValue`/`previewValue`, surfaced on `DependencyValues`, consumed with `@ObservationIgnored @Dependency(\.x)` (view models) or `@Dependency(\.x)` (View structs).
- The getters MUST be `nonisolated` (the module defaults to MainActor isolation, but swift-dependencies' requirements are nonisolated); build backends through a `nonisolated init` or defer isolated work into the client's async/`@MainActor` closures.
- `testValue`/`previewValue` should be inert so tests/previews never hit hardware unless they explicitly override the dependency.
- Migrated: the speech seam, `AnthropicService` (→ `\.wordLookup`), `KeychainService` (→ `\.apiKeyStore`; `seedAPIKeyIfNeeded` stays static — it runs in `@main` before any dependency scope), and `TTSService` (→ `\.speechSynthesizer`, wrapping the shared synthesizer; the static voice query `hasEnhancedVoice` is not injected). `SessionViewModel.lookup()` is now unit-testable end-to-end (`SessionLookupTests`) with all three overridden.

### SwiftData
- Single model: `Word` (schema `CamuseanSchemaV2`) — `word`, `definition`, `exampleSentence`, `sourceLanguage`, `targetLanguage`, `timestamp`, `isKnown` (deprecated, kept on disk for back-compat), plus SM-2 SRS fields `interval`, `easeFactor`, `nextReviewDate` (all with schema-level defaults).
- `ModelContainer` is set up once in `camuseanApp` and injected via `.modelContainer()`.
- **Versioned schema with migration**: V1→V2 lives in `CamuseanMigrationPlan.swift`. New persisted fields need property-level defaults or migration fails with "missing attribute values on mandatory destination attribute".

### API key
- Stored in iOS Keychain via `KeychainService` (Security framework).
- Never hardcoded. User enters it in the Settings tab on first launch.
- Loaded at call time in `SessionViewModel.lookup()`.

## Coding Standards

### Swift style
- Swift 6 strict concurrency — resolve all warnings, not just errors.
- Prefer `@Observable` over `ObservableObject` / `@StateObject` / `@ObservedObject`.
- `async/await` for all async operations.
- `guard` for early exits.
- No force unwraps (`!`) without a comment explaining why it's safe.

### SwiftUI patterns
- Extract views when they exceed ~100 lines.
- `@State` for local view state only.
- `@Environment(\.modelContext)` for SwiftData access in views.
- `@Bindable` for bindings into `@Observable` objects.
- Use `NavigationStack` — not the deprecated `NavigationView`.

### Error handling
- Use typed `LocalizedError` enums (see `LookupError` in `AnthropicService.swift`).
- Surface real error messages in the UI — don't swallow errors with generic strings.
- On API failure: save the word with an empty definition, speak "Couldn't get definition", continue the session.

## Testing
- Framework: **Swift Testing** (`@Test`, `#expect`) — not XCTest.
- Unit tests go in `camuseanTests/`.
- UI tests go in `camuseanUITests/`.
- Priority test targets: `AnthropicService` (mock URLSession), `Word` SwiftData CRUD, `KeychainService`.
- Speech is injected via swift-dependencies — `SessionViewModel()` resolves the inert `NoopSpeechRecognizer` in tests by default; override with `withDependencies { $0.speechRecognizer = ... }` to drive the lookup flow without a mic.
- Manual device tests required for audio (real-mic recognition and TTS don't work in Simulator) — this includes validating the iOS 26 `DictationSpeechRecognizer` path.

## Orca Workflow
This repo is developed inside **Orca** (agent-managed git worktrees). Use the public `orca` CLI (`orca-cli` skill) for anything touching Orca state — prefer it over raw `git worktree`.

### Fresh-worktree setup
- A new worktree runs `scripts/orca-worktree-setup.sh` (set as the repo's Setup script in the Orca app — the CLI can't set it). It seeds `camusean/Secrets.plist` from the primary checkout (that file is gitignored, so a new worktree lacks the seeded API key) and pre-resolves SwiftPM packages.
- If a worktree's builds ship an empty key field, run the setup script manually or `./scripts/set-api-key.sh sk-ant-...`.
- SwiftPM cache, DerivedData, and the Keychain are shared across worktrees on this machine — there is nothing else to "install" per worktree.

### Parallel agents in child worktrees
- Spin up an isolated worktree with its own agent: `orca worktree create --name <task> --agent claude --prompt "<work>"` (branches off `main`; `--parent-worktree active` to record lineage). Prefer `--agent` over create-then-open — it puts the agent in the first terminal.
- Inspect the fleet with `orca worktree ps` / `orca worktree list --json`; drive a worker's terminal with `orca terminal read` / `orca terminal send`.
- Keep parallel worktrees to genuinely independent work — this is a single-model iOS app, so file-level conflicts on `SessionViewModel`/`Word` are the main risk. Rebase or merge back through normal git; use `/ship` to land.
- For a fresh agent in the **current** checkout (no new worktree): `orca terminal create --worktree active --command "claude"`.

### iOS QA in the Orca emulator pane
- `orca emulator list` → `orca emulator attach "iPhone 17 Pro"` (name or UDID from `xcrun simctl list devices`) boots the sim into Orca's emulator pane and scopes it to this worktree.
- Drive it with `orca emulator tap <x> <y>` (normalized 0..1 coords), `orca emulator type <text>`, `orca emulator gesture <json>`, `orca emulator button home`. `orca emulator kill` stops the helper.
- Build/install/launch still go through XcodeBuildMCP (`build_run_sim`); the `orca emulator` layer is for the interactive tap/type QA loop while watching the live view. **Mic + TTS still require a real device** — the Simulator can't exercise the speech path.

## DO NOT
- Use `@AppStorage` inside `@Observable` classes — they clash at the macro expansion level. Use `UserDefaults.standard` computed properties instead.
- Call `AVAudioSession` from a plain `actor` — use `@MainActor` for all audio session management.
- Use the deprecated `@ObservedObject` / `@StateObject` / `ObservableObject` pattern.
- Add features beyond current scope: no user accounts, no cloud sync. (SRS scheduling and multiple reading languages already shipped — those are in-scope, not off-limits.)
- Hardcode the Anthropic API key anywhere in source.
- Use `UIKit` for anything covered by SwiftUI.

## GBrain Configuration (configured by /setup-gbrain)
- Mode: local-stdio
- Engine: pglite (gbrain 0.42.58.0, brain at `~/.gbrain/brain.pglite`)
- Config file: `~/.gbrain/config.json` (mode 0600)
- Embeddings: **deferred (no provider)** — keyword + symbol search only. Semantic search needs an embedding key: `gbrain config set embedding_model voyage:voyage-code-3` (or openai) then re-sync.
- Setup date: 2026-07-12
- MCP registered: yes (user scope) — restart Claude Code sessions to load `mcp__gbrain__*` tools
- Trust policy: personal (local single-tenant)
- Artifacts sync: off (local only)
- Current repo policy: read-write

## GBrain Search Guidance (configured by /sync-gbrain)
<!-- gstack-gbrain-search-guidance:start -->

GBrain is set up and synced on this machine. The agent should prefer gbrain
over Grep when the question is semantic or when you don't know the exact
identifier yet. Two indexed corpora available via the `gbrain` CLI:
- This repo's code (registered as `gstack-code-<repo>` source).
- `~/.gstack/` curated memory (registered as `gstack-brain-<user>` source via
  the existing federation pipeline).

Prefer gbrain when:
- "Where is X handled?" / semantic intent, no exact string yet:
    `gbrain search "<terms>"` or `gbrain query "<question>"`
- "Where is symbol Y defined?" / symbol-based code questions:
    `gbrain code-def <symbol>` or `gbrain code-refs <symbol>`
- "What calls Y?" / "What does Y depend on?":
    `gbrain code-callers <symbol>` / `gbrain code-callees <symbol>`
- "What did we decide last time?" / past plans, retros, learnings:
    `gbrain search "<terms>" --source gstack-brain-<user>`

Grep is still right for known exact strings, regex, multiline patterns, and
file globs. The brain auto-syncs incrementally on every gstack skill start.
Run `/sync-gbrain` to force-refresh, `/sync-gbrain --full` for full reindex.

<!-- gstack-gbrain-search-guidance:end -->

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
