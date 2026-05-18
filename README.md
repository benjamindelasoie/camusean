# Camusean

A voice-first reading companion for foreign-language literature. Say a word you don't know — hear its definition instantly — keep reading.

---

## The problem

Reading a novel in a foreign language means ~10 unknown words per page. The usual flow: put the book down, unlock your phone, switch to a dictionary app, type the word, read the definition, lose your place. That's four steps and a broken flow state for every unfamiliar word.

## The solution

Camusean listens while you read. Say a word out loud — the app transcribes it, asks Claude for a contextual definition and example sentence, and reads it back through your earphones in under two seconds. Your hands stay on the book.

Saved words appear as flashcards in a review tab so nothing is lost.

## How it works

1. Open the **Reading** tab and start a session
2. Say any foreign word aloud — the app is always listening
3. Hear the definition and an example sentence read back via TTS
4. Swipe through saved words in the **Review** tab as flashcards

## Stack

- **Swift 6 + SwiftUI + SwiftData** — iOS 18+, no external packages
- **SFSpeechRecognizer** — on-device speech-to-text with auto silence detection
- **AVSpeechSynthesizer** — TTS with premium/enhanced voice selection
- **Claude Haiku** (`claude-haiku-4-5-20251001`) — fast, cheap definitions via the Anthropic API
- **iOS Keychain** — API key stored locally, never leaves the device
- No backend, no accounts, no telemetry

## Setup

1. Clone and open `camusean.xcodeproj` in Xcode 16+
2. Select your target device (iOS 18 required) and run
3. Go to **Settings**, paste your [Anthropic API key](https://console.anthropic.com/), and pick your source language

## Project structure

```
camusean/
├── App/
├── Features/
│   ├── Reading/      session view + view model (listen → lookup → speak)
│   ├── Review/       flashcard swipe UI
│   └── Settings/     language picker + API key entry
└── Core/
    ├── Models/       Word (SwiftData)
    └── Services/     AnthropicService, SpeechService, TTSService,
                      AudioSessionManager, KeychainService
```

## Privacy

Everything runs on-device or directly between the app and the Anthropic API using your own key. No user data is collected or stored remotely.

## License

[AGPL-3.0](LICENSE) — Copyright (c) 2026 Benjamin Delasoie.
