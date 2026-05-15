import Foundation
import SwiftData
import Observation

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

    private let sessionCap = 50
    private let speechService = SpeechService()
    private let anthropicService = AnthropicService()
    private let tts = TTSService.shared
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
        phase = .idle
    }

    func endSession() {
        speechService.reset()
        AudioSessionManager.shared.deactivate()
        tts.stopSpeaking()
        isSessionActive = false
        showSummary = true
        phase = .idle
    }

    func onMicPressed() async {
        guard lookupCount < sessionCap else {
            phase = .error("Session limit of \(sessionCap) lookups reached. Words saved.")
            endSession()
            return
        }
        tts.stopSpeaking()
        phase = .listening
        await speechService.startListening()
    }

    func onMicReleased() async {
        guard case .listening = phase else { return }
        phase = .idle

        guard let word = await speechService.finishAndTranscribe(),
              !word.trimmingCharacters(in: .whitespaces).isEmpty else {
            phase = .idle
            return
        }

        await lookup(word: word)
    }

    private func lookup(word: String) async {
        phase = .processing(word)

        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            phase = .error("No API key set. Add your Anthropic key in Settings.")
            saveWord(word: word, definition: "", example: "")
            return
        }

        do {
            let result = try await anthropicService.lookup(
                word: word,
                sourceLanguage: sourceName,
                targetLanguage: targetName,
                apiKey: apiKey
            )
            saveWord(word: word, definition: result.definition, example: result.exampleSentence)
            lookupCount += 1
            phase = .result(word, result.definition)
            try? await AudioSessionManager.shared.activateForPlayback()
            await tts.speak("\(word). \(result.definition)")
            try? await AudioSessionManager.shared.activateForRecording()
        } catch {
            let msg = error.localizedDescription
            saveWord(word: word, definition: "", example: "")
            phase = .error(msg)
            try? await AudioSessionManager.shared.activateForPlayback()
            await tts.speak("Couldn't get definition")
            try? await AudioSessionManager.shared.activateForRecording()
        }

        if case .error = phase {} else { phase = .idle }
    }

    private func saveWord(word: String, definition: String, example: String) {
        guard let context = modelContext else { return }
        let entry = Word(
            word: word,
            definition: definition,
            exampleSentence: example,
            sourceLanguage: sourceName,
            targetLanguage: targetName
        )
        context.insert(entry)
        try? context.save()
    }
}
