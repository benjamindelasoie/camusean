import Foundation
import SwiftData
import Observation
import UIKit
import Dependencies

enum SessionPhase {
    case idle
    case listening
    case processing(String)
    // formNote is shown on the result card but must never reach TTS (see LookupResult.formNote).
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

    // iOS won't re-prompt after a denial, so the start screen offers an "Open Settings" path.
    var permissionDenied = false

    // Here so the view doesn't import UIKit.
    let settingsURLString = UIApplication.openSettingsURLString

    var partialTranscription: String { speechService.partialTranscription }

    // Mirrored from the recognizer for the debug overlay: it's a bare `any SpeechRecognizing`
    // existential SwiftUI can't observe, so the listening loop copies these out.
    var debugBackendName = ""
    var debugLocaleSupported: Bool? = nil
    var debugLastError: String? = nil
    var lastCandidates: [String] = []

    var debugPhaseLabel: String { Self.phaseLabel(phase) }

    // Cancel + biased-retry state. Internal (not private) so tests can read it via @testable import.
    var currentWord: Word?
    var lookupCancelled: Bool = false
    var recentlyRejected: [(transcription: String, at: Date)] = []

    // Tracked apart from `currentWord` because correction rewrites `currentWord.word` to the
    // intended word: on reject we must blocklist what was actually misheard, not the correction.
    var currentOriginalTranscription: String?

    let rejectionWindowSeconds: TimeInterval = 10
    let rejectionCap: Int = 3

    private let sessionCap = 50
    // @ObservationIgnored: @Dependency is its own wrapper and must not be re-wrapped by @Observable.
    @ObservationIgnored @Dependency(\.speechRecognizer) private var speechService
    @ObservationIgnored @Dependency(\.wordLookup) private var wordLookup
    @ObservationIgnored @Dependency(\.apiKeyStore) private var apiKeyStore
    @ObservationIgnored @Dependency(\.speechSynthesizer) private var synth
    private var listeningTask: Task<Void, Never>?
    var modelContext: ModelContext?

    // The book being read (nil = free session). When it carries a language it overrides the global
    // reading language for the session, sharpens the lookup prompt, and tags every saved word.
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

    // e.g. "L'Étranger by Albert Camus" — sharpens the lookup prompt; nil for a free session.
    private var bookContext: String? {
        guard let book = activeBook else { return nil }
        let title = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let author = book.author.trimmingCharacters(in: .whitespacesAndNewlines)
        return author.isEmpty ? title : "\(title) by \(author)"
    }

    // Kill-switch for LLM word correction (Settings → Developer, default ON). When OFF the lookup
    // still logs the would-be correction but applies nothing.
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
        // A call or Siri tears the audio session away; without this the UI shows "listening"
        // over a dead engine.
        AudioSessionManager.shared.onInterruption = { [weak self] in
            guard let self, self.isSessionActive else { return }
            self.endSession()
        }

        listeningTask = Task {
            while !Task.isCancelled {
                phase = .listening
                let candidates = await speechService.listenForCandidates()

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
        synth.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        isSessionActive = false
        showSummary = true
        phase = .idle
    }

    // Stop TTS, delete the just-saved Word, blocklist the rejected transcription, return to listening.
    func cancelCurrentLookup() {
        // Prefer the raw transcription so we blocklist what was misheard, not the correction that
        // replaced it. Fall back to currentWord/the phase for cancels that predate it being set.
        let transcription: String? = currentOriginalTranscription ?? {
            if let w = currentWord { return w.word }
            if case .processing(let p) = phase { return p }
            if case .result(let r, _, _) = phase { return r }
            return nil
        }()

        lookupCancelled = true
        synth.stop()

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

    nonisolated static func phaseLabel(_ phase: SessionPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .listening: return "listening"
        case .processing(let w): return "processing(\(w))"
        case .result(let w, _, _): return "result(\(w))"
        case .error: return "error"
        }
    }

    // Drops candidates matching a recent rejection (within the TTL, last `cap`, case-insensitive).
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

    // The reader was handed a capped key they don't see, so failures must never say "check Settings".
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

        lookupCancelled = false
        phase = .processing(word)

        guard let apiKey = apiKeyStore.load(), !apiKey.isEmpty else {
            phase = .error("No API key set. Add your Anthropic key in Settings.")
            _ = saveWord(word: word, definition: "", example: "")
            return
        }

        // Set only once we're committed to the call, so the no-API-key bail can't leave a stale value.
        currentOriginalTranscription = word

        // Fetch the definition and echo the word back concurrently: pronouncing the native word
        // hides the network round-trip. Rejected mishearings go as negative context.
        async let pending = wordLookup.lookup(
            word,
            sourceName,
            targetName,
            bookContext,
            recentlyRejected.map(\.transcription),
            apiKey
        )

        try? AudioSessionManager.shared.activateForPlayback()
        await synth.speak(word, sourceLocale)
        if lookupCancelled {
            _ = try? await pending  // drain the in-flight request so the async let isn't left dangling
            return
        }

        do {
            let result = try await pending
            if lookupCancelled { return }

            // Apply the correction only when the kill-switch is on; log it either way.
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

            // The concurrent echo already spoke the misheard word; voice the corrected one (in the
            // source locale) before the definition so the reader hears the right pronunciation.
            if let corrected = appliedCorrection {
                await synth.speak(corrected, sourceLocale)
                if lookupCancelled { return }
            }

            // formNote is never spoken: it carries source-language text the en-US voice mangles.
            await synth.speak(result.definition, "en-US")
            if lookupCancelled { return }

            try? AudioSessionManager.shared.activateForRecording()

            // Accepted lookup: clear in-flight state and the rejection blocklist.
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
            await synth.speak("Couldn't get definition", "en-US")
            if lookupCancelled { return }
            try? AudioSessionManager.shared.activateForRecording()
            currentWord = nil
            currentOriginalTranscription = nil
        }
    }

#if DEBUG
    // QA hook: drive the full lookup path without a mic. Launch with `-qaWord <word>` (see ReadingSessionView).
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
