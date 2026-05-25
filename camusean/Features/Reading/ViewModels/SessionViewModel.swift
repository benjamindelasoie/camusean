import Foundation
import SwiftData
import Observation
import UIKit

enum SessionPhase {
    case idle
    case listening
    case processing(String)
    case result(String, String)  // word, definition
    case error(String)
}

@Observable
@MainActor
final class SessionViewModel {
    var phase: SessionPhase = .idle
    var isSessionActive = false
    var lookupCount = 0
    var showSummary = false

    var partialTranscription: String { speechService.partialTranscription }

    // Cancel + biased-retry state (locked by /plan-eng-review 2026-05-23).
    // Internal (not private) so test target can read via @testable import.
    var currentWord: Word?
    var lookupCancelled: Bool = false
    var recentlyRejected: [(transcription: String, at: Date)] = []

    let rejectionWindowSeconds: TimeInterval = 10
    let rejectionCap: Int = 3

    private let sessionCap = 50
    private let speechService = SpeechService()
    private let anthropicService = AnthropicService()
    private let tts = TTSService.shared
    private var listeningTask: Task<Void, Never>?
    var modelContext: ModelContext?

    var sourceLocale: String { UserDefaults.standard.string(forKey: "sourceLanguageLocale") ?? "fr-FR" }
    var sourceName: String { UserDefaults.standard.string(forKey: "sourceLanguageName") ?? "French" }
    var targetName: String { UserDefaults.standard.string(forKey: "targetLanguageName") ?? "English" }

    func startSession() async {
        let granted = await speechService.requestPermissions()
        guard granted else {
            phase = .error("Microphone or speech recognition permission denied. Go to Settings to allow access.")
            return
        }
        speechService.setLocale(sourceLocale)
        isSessionActive = true
        lookupCount = 0
        UIApplication.shared.isIdleTimerDisabled = true

        listeningTask = Task {
            while !Task.isCancelled {
                phase = .listening
                let candidates = await speechService.listenForCandidates()
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
        // Capture the transcription BEFORE mutating state. Prefer currentWord (set after
        // saveWord); fall back to the phase enum (cancel fired before saveWord ran).
        let transcription: String? = {
            if let w = currentWord { return w.word }
            if case .processing(let p) = phase { return p }
            if case .result(let r, _) = phase { return r }
            return nil
        }()

        lookupCancelled = true
        tts.stopSpeaking()

        if let word = currentWord {
            modelContext?.delete(word)
            try? modelContext?.save()
        }
        currentWord = nil

        if let t = transcription {
            recentlyRejected.append((transcription: t, at: Date()))
        }

        phase = .listening
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

        do {
            let result = try await anthropicService.lookup(
                word: word,
                sourceLanguage: sourceName,
                targetLanguage: targetName,
                apiKey: apiKey
            )
            if lookupCancelled { return }

            currentWord = saveWord(word: word, definition: result.definition, example: result.exampleSentence)
            lookupCount += 1
            phase = .result(word, result.definition)

            try? AudioSessionManager.shared.activateForPlayback()
            await tts.speak(word, language: sourceLocale)
            if lookupCancelled { return }

            await tts.speak(result.definition, language: "en-US")
            if lookupCancelled { return }

            try? AudioSessionManager.shared.activateForRecording()

            // Successful uncancelled completion: clear in-flight state and the rejection
            // blocklist (user accepted the lookup, so prior rejections are no longer relevant).
            currentWord = nil
            recentlyRejected = []
        } catch {
            if lookupCancelled { return }
            let msg = error.localizedDescription
            currentWord = saveWord(word: word, definition: "", example: "")
            phase = .error(msg)
            try? AudioSessionManager.shared.activateForPlayback()
            await tts.speak("Couldn't get definition")
            if lookupCancelled { return }
            try? AudioSessionManager.shared.activateForRecording()
            currentWord = nil
        }
    }

    @discardableResult
    private func saveWord(word: String, definition: String, example: String) -> Word? {
        guard let context = modelContext else { return nil }
        let entry = Word(
            word: word,
            definition: definition,
            exampleSentence: example,
            sourceLanguage: sourceName,
            targetLanguage: targetName
        )
        context.insert(entry)
        try? context.save()
        return entry
    }
}
