import Foundation
import Speech
import AVFoundation

// The app's speech-to-text seam. Two backends implement this contract:
//   • LegacySpeechRecognizer    — SFSpeechRecognizer (iOS 18–25)
//   • DictationSpeechRecognizer  — SpeechAnalyzer + DictationTranscriber (iOS 26+)
//
// SessionViewModel depends only on this protocol; `SpeechRecognition.make()` picks the
// backend for the running OS. `Sendable` so the existential can be vended as a
// swift-dependencies value; the conforming backends are `@MainActor` classes (implicitly
// `Sendable`), and requirements stay `@MainActor`-isolated.
@MainActor
protocol SpeechRecognizing: AnyObject, Sendable {
    var partialTranscription: String { get }

    // MARK: Diagnostics (read by the on-screen session debug overlay)

    /// Human-readable name of the active backend, e.g. "Dictation · SpeechAnalyzer (iOS 26)".
    var backendName: String { get }

    /// Whether the source locale is supported. `nil` until the first `listenForCandidates()`.
    var localeSupported: Bool? { get }

    var lastErrorMessage: String? { get }

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
    /// iOS 26+ gets `DictationTranscriber`; older systems keep the `SFSpeechRecognizer` path.
    /// `nonisolated` so it can be called from the swift-dependencies `liveValue` getter; the
    /// backends' `init`s are likewise nonisolated (constructing them touches no main-actor state).
    nonisolated static func make() -> any SpeechRecognizing {
        if #available(iOS 26, *) {
            return DictationSpeechRecognizer()
        } else {
            return LegacySpeechRecognizer()
        }
    }

    // MUST stay `nonisolated`. TCC delivers these completion handlers on a background dispatch
    // queue. Under @MainActor isolation Swift 6 inserts a main-executor assertion that runs before
    // the closure body — off the main queue it trips `dispatch_assert_queue` → SIGTRAP (crashed on
    // first "Begin Reading", iOS 26 build). A nonisolated context strips that isolation; resuming a
    // CheckedContinuation from a background thread is safe and Sendable.
    nonisolated static func requestMicAndSpeechAuthorization() async -> Bool {
        let speechAuth = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micAuth = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        return speechAuth && micAuth
    }

    // Shared by both backends so they dedupe candidates identically. Dedupes case-insensitively,
    // keeping first occurrence and its original casing.
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
