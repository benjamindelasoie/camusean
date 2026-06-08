import Foundation

// The app's speech-to-text seam. Two backends implement this contract:
//   • LegacySpeechRecognizer    — SFSpeechRecognizer (iOS 18–25)
//   • DictationSpeechRecognizer  — SpeechAnalyzer + DictationTranscriber (iOS 26+)
//
// SessionViewModel depends only on this protocol; `SpeechRecognition.make()` picks
// the best backend for the running OS. Keeping the seam here means the iOS 26 path
// is a drop-in: nothing in the view model knows which engine is recognizing speech.
// (This is also the exact seam that gets registered with swift-dependencies next.)
// `Sendable` so the existential can be vended as a swift-dependencies value (which
// requires `Value: Sendable`); the conforming backends are `@MainActor` classes, which
// are implicitly `Sendable`. Requirements stay `@MainActor`-isolated.
@MainActor
protocol SpeechRecognizing: AnyObject, Sendable {
    /// Live transcription shown while the user is still speaking.
    var partialTranscription: String { get }

    /// Set the source-language locale (e.g. "fr-FR") before listening.
    func setLocale(_ identifier: String)

    /// Request microphone + speech-recognition permission. Returns whether both were granted.
    func requestPermissions() async -> Bool

    /// Listen for a single spoken utterance and return up to 3 distinct candidate
    /// transcriptions (best first), or `[]` on no-speech / cancellation / error.
    func listenForCandidates() async -> [String]

    /// Hard-stop: resolve any in-flight `listenForCandidates()` with `[]` and tear down audio.
    func reset()
}

enum SpeechRecognition {
    /// Pick the best available speech backend for the running OS.
    /// iOS 26+ gets Apple's on-device `DictationTranscriber`; older systems keep
    /// the `SFSpeechRecognizer` path that has always shipped.
    ///
    /// `nonisolated` so it can be called from the swift-dependencies `liveValue`
    /// getter (which is nonisolated). The backends' `init`s are likewise nonisolated —
    /// constructing them touches no main-actor state.
    nonisolated static func make() -> any SpeechRecognizing {
        if #available(iOS 26, *) {
            return DictationSpeechRecognizer()
        } else {
            return LegacySpeechRecognizer()
        }
    }

    // Pure string-level helper shared by both backends. (Moved here from the old
    // SpeechService so the iOS 26 path reuses the exact same candidate-dedup rules.)
    //
    // Behavior: trims whitespace, drops empty entries, dedupes case-insensitively
    // (keeping first occurrence and its original casing), caps at `max` entries.
    static func extractDistinctTranscriptions(from strings: [String], max: Int = 3) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for s in strings {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
                if result.count >= max { break }
            }
        }
        return result
    }
}
