# Project: Camusean

Voice reading companion — say a foreign word aloud during a reading session, hear the definition instantly, review saved words as flashcards later.

## Quick Reference
- **Platform**: iOS 18+
- **Language**: Swift 6.0 (strict concurrency enabled)
- **UI Framework**: SwiftUI
- **Architecture**: MVVM with `@Observable`
- **Persistence**: SwiftData
- **Package Manager**: Swift Package Manager (no external packages currently)
- **Bundle ID**: com.bdelasoie.camusean

## XcodeBuildMCP Integration
**IMPORTANT**: This project uses XcodeBuildMCP for all Xcode operations.
- Build: `mcp__xcodebuildmcp__build_sim_name_proj`
- Test: `mcp__xcodebuildmcp__test_sim_name_proj`
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
            ├── AnthropicService.swift        # Claude Haiku API calls via URLSession
            ├── AudioSessionManager.swift     # AVAudioSession lifecycle (@MainActor)
            ├── KeychainService.swift         # API key storage (Security framework)
            ├── SpeechService.swift           # SFSpeechRecognizer, push-to-talk
            └── TTSService.swift              # AVSpeechSynthesizer (@MainActor delegate)
```

> **Note**: Xcode auto-discovers all `.swift` files in this directory via filesystem sync — no need to manually add files to the project. Just create the file on disk and it's included.

## Architecture

### Concurrency rules
- All UI state lives in `@Observable @MainActor` classes.
- Use `async/await` everywhere. No `DispatchQueue`, no completion handlers.
- `AVAudioSession` must be called from `@MainActor` — use `AudioSessionManager.shared`.
- `TTSService` must be `@MainActor NSObject` to satisfy `AVSpeechSynthesizerDelegate` (Objective-C delegate + Swift 6 strict concurrency requirement).
- `SFSpeechRecognizer` callbacks arrive on background threads — always hop to `@MainActor` with `Task { @MainActor in ... }`.

### SwiftData
- Single model: `Word` — `word`, `definition`, `exampleSentence`, `sourceLanguage`, `targetLanguage`, `timestamp`, `isKnown: Bool`.
- `ModelContainer` is set up once in `camuseanApp` and injected via `.modelContainer()`.
- No migrations needed yet (MVP, single model, no schema changes).

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
- Manual device tests required for audio (speech recognition and TTS don't work in Simulator).

## DO NOT
- Use `@AppStorage` inside `@Observable` classes — they clash at the macro expansion level. Use `UserDefaults.standard` computed properties instead.
- Call `AVAudioSession` from a plain `actor` — use `@MainActor` for all audio session management.
- Use the deprecated `@ObservedObject` / `@StateObject` / `ObservableObject` pattern.
- Add features beyond MVP scope: no user accounts, no cloud sync, no SRS algorithm, no multiple language pairs (yet).
- Hardcode the Anthropic API key anywhere in source.
- Use `UIKit` for anything covered by SwiftUI.
