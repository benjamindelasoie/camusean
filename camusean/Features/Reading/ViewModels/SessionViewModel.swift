import Foundation
import SwiftData
import Observation
import UIKit
import Dependencies

enum SessionPhase {
    case idle
    case listening
    case processing(String)
    // word, definition, formNote. `formNote` is rendered on the result card but must never be
    // handed to TTS — it deliberately contains source-language text (see LookupResult.formNote).
    case result(String, String, String?)
    case error(String)
}

@Observable
@MainActor
final class SessionViewModel {
    var phase: SessionPhase = .idle
    var isSessionActive = false
    var lookupCount = 0
    var showSummary = false

    // Set when mic/speech permission is denied. iOS won't re-prompt after a denial,
    // so the start screen shows an "Open Settings" path instead of a terminal red message.
    var permissionDenied = false

    // The Settings deep-link is exposed here so the view doesn't import UIKit.
    let settingsURLString = UIApplication.openSettingsURLString

    var partialTranscription: String { speechService.partialTranscription }

    // Mirrored recognizer diagnostics for the session debug overlay. The recognizer is held
    // as `@ObservationIgnored @Dependency` and typed as a bare `any SpeechRecognizing`
    // existential, so SwiftUI can't observe changes inside it — we copy the values into these
    // stored @Observable props from the @MainActor listening loop so the HUD updates live.
    var debugBackendName = ""
    var debugLocaleSupported: Bool? = nil
    var debugLastError: String? = nil
    var lastCandidates: [String] = []

    var debugPhaseLabel: String { Self.phaseLabel(phase) }

    // Cancel + biased-retry state (locked by /plan-eng-review 2026-05-23).
    // Internal (not private) so test target can read via @testable import.
    var currentWord: Word?
    var lookupCancelled: Bool = false
    var recentlyRejected: [(transcription: String, at: Date)] = []

    // The raw ASR transcription for the in-flight lookup, tracked separately from `currentWord`
    // because correction rewrites `currentWord.word` to the *intended* word. On reject we must
    // blocklist what was actually misheard (the transcription), not the corrected word, or the
    // biased-retry filter and the negative-context prompt key off the wrong token.
    var currentOriginalTranscription: String?

    let rejectionWindowSeconds: TimeInterval = 10
    let rejectionCap: Int = 3

    private let sessionCap = 50
    // Resolved through swift-dependencies: the live OS-appropriate recognizer in the app,
    // an overridable seam in tests/previews. @ObservationIgnored because @Dependency is its
    // own property wrapper and must not be wrapped again by @Observable.
    @ObservationIgnored @Dependency(\.speechRecognizer) private var speechService
    private let anthropicService = AnthropicService()
    private let tts = TTSService.shared
    private var listeningTask: Task<Void, Never>?
    var modelContext: ModelContext?

    // The book this session is reading, or nil for a "free" session. Set on the start screen
    // before startSession(). When set (and it carries a language), it overrides the global Settings
    // reading language for the session, its title/author sharpen the lookup prompt, and every saved
    // word is tagged to it.
    var activeBook: Book?

    var sourceLocale: String {
        if let lang = activeBook?.language, !lang.isEmpty { return lang }
        return UserDefaults.standard.string(forKey: "sourceLanguageLocale") ?? "fr-FR"
    }
    var sourceName: String {
        if let lang = activeBook?.language, !lang.isEmpty { return ReadingLanguage.named(locale: lang).name }
        return UserDefaults.standard.string(forKey: "sourceLanguageName") ?? "French"
    }
    var targetName: String { UserDefaults.standard.string(forKey: "targetLanguageName") ?? "English" }

    // Prompt context: what the reader is currently reading, e.g. "L'Étranger by Albert Camus".
    // nil for a free session. Helps Claude disambiguate a word's sense within the book.
    private var bookContext: String? {
        guard let book = activeBook else { return nil }
        let title = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let author = book.author.trimmingCharacters(in: .whitespacesAndNewlines)
        return author.isEmpty ? title : "\(title) by \(author)"
    }

    // Kill-switch for LLM word correction (Settings → Developer). Defaults ON. When OFF the
    // lookup still logs what Claude *would* have corrected to (so the false-correction rate is
    // observable) but applies nothing — the design's "log without applying" safe-rollout mode.
    var wordCorrectionEnabled: Bool {
        UserDefaults.standard.object(forKey: "wordCorrectionEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "wordCorrectionEnabled")
    }

    func startSession() async {
        permissionDenied = false
        let granted = await speechService.requestPermissions()
        guard granted else {
            permissionDenied = true
            phase = .error("Microphone and speech access are off. Turn them on to look up words by voice.")
            return
        }
        speechService.setLocale(sourceLocale)
        isSessionActive = true
        lookupCount = 0
        UIApplication.shared.isIdleTimerDisabled = true
        // A phone call or Siri tears the audio session out from under the recognizer. Without
        // this the UI keeps showing "listening" over a dead engine.
        AudioSessionManager.shared.onInterruption = { [weak self] in
            guard let self, self.isSessionActive else { return }
            self.endSession()
        }

        listeningTask = Task {
            while !Task.isCancelled {
                phase = .listening
                let candidates = await speechService.listenForCandidates()

                // Mirror recognizer diagnostics for the debug overlay (we're on @MainActor here).
                lastCandidates = candidates
                debugBackendName = speechService.backendName
                debugLocaleSupported = speechService.localeSupported
                debugLastError = speechService.lastErrorMessage

                guard !Task.isCancelled else { break }

                let filtered = Self.filterCandidates(
                    candidates,
                    rejecting: recentlyRejected,
                    window: rejectionWindowSeconds,
                    cap: rejectionCap,
                    now: Date()
                )

                if let word = filtered.first {
                    await lookup(word: word)
                }
            }
        }
    }

    func endSession() {
        listeningTask?.cancel()
        listeningTask = nil
        speechService.reset()
        AudioSessionManager.shared.onInterruption = nil
        AudioSessionManager.shared.deactivate()
        tts.stopSpeaking()
        UIApplication.shared.isIdleTimerDisabled = false
        isSessionActive = false
        showSummary = true
        phase = .idle
    }

    // Cancel the current in-flight lookup: stop TTS, delete the just-saved Word (if any),
    // remember the rejected transcription so the next ASR pass biases away from it,
    // and return to listening.
    func cancelCurrentLookup() {
        // Capture the transcription BEFORE mutating state. Prefer the raw ASR transcription
        // (`currentOriginalTranscription`) so we blocklist what was actually misheard, not the
        // corrected word that replaced it in `currentWord`. Fall back to `currentWord`/the phase
        // enum for cancels that predate the transcription being set (and for the test seams).
        let transcription: String? = currentOriginalTranscription ?? {
            if let w = currentWord { return w.word }
            if case .processing(let p) = phase { return p }
            if case .result(let r, _, _) = phase { return r }
            return nil
        }()

        lookupCancelled = true
        tts.stopSpeaking()

        if let word = currentWord {
            modelContext?.delete(word)
            try? modelContext?.save()
        }
        currentWord = nil
        currentOriginalTranscription = nil

        if let t = transcription {
            recentlyRejected.append((transcription: t, at: Date()))
        }

        phase = .listening
    }

    // Compact label for the current phase, shown in the session debug overlay.
    nonisolated static func phaseLabel(_ phase: SessionPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .listening: return "listening"
        case .processing(let w): return "processing(\(w))"
        case .result(let w, _, _): return "result(\(w))"
        case .error: return "error"
        }
    }

    // Pure helper. Filters out candidates that match a recent rejection within the TTL,
    // capped to the last `cap` rejections (most recent wins). Case-insensitive match.
    nonisolated static func filterCandidates(
        _ candidates: [String],
        rejecting recentlyRejected: [(transcription: String, at: Date)],
        window: TimeInterval = 10,
        cap: Int = 3,
        now: Date = Date()
    ) -> [String] {
        let activeRejections = recentlyRejected
            .filter { now.timeIntervalSince($0.at) <= window }
            .suffix(cap)
        let rejectedSet = Set(activeRejections.map { $0.transcription.lowercased() })
        return candidates.filter { !rejectedSet.contains($0.lowercased()) }
    }

    // Reader-facing copy for a failed lookup. The reader doesn't own (or see) the API key —
    // they were handed a capped one — so auth/billing/server failures must never tell them to
    // "check Settings". Technical detail is preserved in logs (AnthropicService + the catch print).
    nonisolated static func friendlyLookupMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You're offline — the word is saved, but I couldn't fetch its definition."
            case .timedOut:
                return "That took too long. The word is saved; try saying it again."
            default:
                break
            }
        }
        return "Couldn't reach the dictionary right now. The word is saved to review."
    }

    private func lookup(word: String) async {
        guard lookupCount < sessionCap else {
            phase = .error("Session limit of \(sessionCap) lookups reached. Words saved.")
            endSession()
            return
        }

        // Reset cancel flag at the start of each new lookup.
        lookupCancelled = false
        phase = .processing(word)

        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            phase = .error("No API key set. Add your Anthropic key in Settings.")
            _ = saveWord(word: word, definition: "", example: "")
            return
        }

        // Track the raw transcription only once we're committed to the network call, so a
        // failed precondition (no API key) can't leave a stale value for a later cancel.
        currentOriginalTranscription = word

        // Kick off the definition fetch and echo the word back concurrently. The user just
        // said this word, so we can pronounce the "correct" native version while Claude is
        // still generating the definition — the echo hides the network round-trip instead of
        // stacking on top of it. We pass the rejected mishearings as negative context so a
        // repeated misfire biases Claude away from the same wrong interpretation.
        async let pending = anthropicService.lookup(
            word: word,
            sourceLanguage: sourceName,
            targetLanguage: targetName,
            bookContext: bookContext,
            recentlyRejected: recentlyRejected.map(\.transcription),
            apiKey: apiKey
        )

        try? AudioSessionManager.shared.activateForPlayback()
        await tts.speak(word, language: sourceLocale)
        if lookupCancelled {
            _ = try? await pending  // drain the in-flight request so the async let isn't left dangling
            return
        }

        do {
            let result = try await pending
            if lookupCancelled { return }

            // The transcription may have been a mishearing; `result.correctedWord` is the word
            // Claude believes was intended (nil = no correction). Apply it only when the
            // kill-switch is on; either way, log the would-be correction so the false-correction
            // rate is observable on-device before we trust it (the design's safe-rollout).
            let appliedCorrection = wordCorrectionEnabled ? result.correctedWord : nil
            let resolvedWord = appliedCorrection ?? word
            if let intended = result.correctedWord {
                print("[correction] heard=\"\(word)\" intended=\"\(intended)\" applied=\(wordCorrectionEnabled)")
            }

            currentWord = saveWord(
                word: resolvedWord,
                definition: result.definition,
                example: result.exampleSentence,
                formNote: result.formNote
            )
            lookupCount += 1
            phase = .result(resolvedWord, result.definition, result.formNote)

            // If we corrected the word, the concurrent echo already spoke the *misheard* word.
            // Voice the authoritative corrected word (in the source locale) before the English
            // definition so the reader hears the right pronunciation — "<corrected> means <def>".
            if let corrected = appliedCorrection {
                await tts.speak(corrected, language: sourceLocale)
                if lookupCancelled { return }
            }

            // Only the definition is spoken. `result.formNote` is deliberately NOT passed to TTS:
            // it carries source-language text (a lemma or infinitive), and the en-US voice mangles
            // those — the exact bug that motivated splitting it out of `definition`.
            await tts.speak(result.definition, language: "en-US")
            if lookupCancelled { return }

            try? AudioSessionManager.shared.activateForRecording()

            // Successful uncancelled completion: clear in-flight state and the rejection
            // blocklist (user accepted the lookup, so prior rejections are no longer relevant).
            currentWord = nil
            currentOriginalTranscription = nil
            recentlyRejected = []
        } catch {
            if lookupCancelled { return }
            print("[lookup] error: \(error)")
            // On failure there is no correction — persist the raw transcription unchanged.
            currentWord = saveWord(word: word, definition: "", example: "")
            phase = .error(Self.friendlyLookupMessage(for: error))
            try? AudioSessionManager.shared.activateForPlayback()
            await tts.speak("Couldn't get definition")
            if lookupCancelled { return }
            try? AudioSessionManager.shared.activateForRecording()
            currentWord = nil
            currentOriginalTranscription = nil
        }
    }

#if DEBUG
    // QA hook: simulate a word being "heard" without the microphone, driving the
    // full lookup → Haiku → save → TTS path. /ios-qa can drive synthetic touch but
    // cannot speak, so this is how the core retrieval flow gets exercised on-device.
    // Triggered by launching with `-qaWord <word>` (see ReadingSessionView).
    func debugSimulateHeardWord(_ word: String) async {
        isSessionActive = true            // render the session screen so the result shows
        UIApplication.shared.isIdleTimerDisabled = true
        await lookup(word: word)
    }
#endif

    @discardableResult
    private func saveWord(word: String, definition: String, example: String, formNote: String? = nil) -> Word? {
        guard let context = modelContext else { return nil }
        let entry = Word(
            word: word,
            definition: definition,
            exampleSentence: example,
            sourceLanguage: sourceName,
            targetLanguage: targetName,
            book: activeBook,
            formNote: formNote
        )
        context.insert(entry)
        try? context.save()
        return entry
    }
}
