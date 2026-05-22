import AVFoundation

@MainActor
final class TTSService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = TTSService()
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: String = "en-US") async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = bestVoice(for: language)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synthesizer.speak(utterance)
        }
    }

    private func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language.prefix(2)) }
        return candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    // True if an Enhanced or Premium voice is installed for `language` (matches by 2-letter prefix).
    // Without one, AVSpeechSynthesizer falls back to the compact default and sounds robotic.
    // Users must download enhanced voices in iOS Settings -> Accessibility -> Spoken Content.
    static func hasEnhancedVoice(forLanguagePrefix prefix: String) -> Bool {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .contains { $0.quality == .enhanced || $0.quality == .premium }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.continuation?.resume()
            self.continuation = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}
