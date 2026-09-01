import AVFoundation
import Dependencies

// Speech output. One synthesizer, shared by the reading session and the review deck.
//
// speak() is INTERRUPT-AND-REPLACE: a second call cuts the first off and its `await` returns.
// There is one continuation slot and delegate callbacks arrive out of band, so `finish` resumes
// only for the utterance the slot currently belongs to — otherwise a stale didCancel for the
// previous utterance would resume the new caller while it is still speaking.
//
//   speak(A) ──▶ continuation = cA, currentUtterance = A ──▶ synthesizer.speak(A)
//   speak(B) ──▶ cA.resume()  ← A unblocks; stopSpeaking queues didCancel(A); slot = cB / B
//   didCancel(A) ──▶ A !== currentUtterance (now B) ──▶ ignored
//   didFinish(B) ──▶ B === currentUtterance ──▶ cB.resume()
@MainActor
final class TTSService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = TTSService()
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    /// The utterance the stored continuation belongs to; callbacks for any other are stale.
    private var currentUtterance: AVSpeechUtterance?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: String = "en-US") async {
        // Release the previous waiter before taking the slot.
        continuation?.resume()
        continuation = nil
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)

        await withCheckedContinuation { continuation in
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = bestVoice(for: language)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            self.continuation = continuation
            self.currentUtterance = utterance
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

    // Without an Enhanced/Premium voice the synthesizer falls back to the compact voice and
    // sounds robotic (users install voices in Settings › Accessibility › Spoken Content).
    static func hasEnhancedVoice(forLanguagePrefix prefix: String) -> Bool {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .contains { $0.quality == .enhanced || $0.quality == .premium }
    }

    /// Stops in-flight speech and unblocks its caller. Safe when nothing is speaking.
    func stopSpeaking() {
        continuation?.resume()
        continuation = nil
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Resume the waiter only if the callback is for the utterance the slot belongs to. Compared
    /// by `ObjectIdentifier` because `AVSpeechUtterance` isn't `Sendable` and can't cross from the
    /// nonisolated delegate; `currentUtterance` holds a strong ref so the address can't be recycled.
    private func finish(_ id: ObjectIdentifier) {
        guard let current = currentUtterance, ObjectIdentifier(current) == id else {
            return   // stale: superseded by a newer speak()
        }
        continuation?.resume()
        continuation = nil
        currentUtterance = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id) }
    }
}

// swift-dependencies seam (closure-client idiom), forwarding to the shared synthesizer so output
// can be overridden in the reading flow and previews. `stop` is a sync `@MainActor` call so the
// non-async teardown paths (`endSession`, `cancelCurrentLookup`) cut speech without a Task.
struct SpeechSynthesizerClient: Sendable {
    var speak: @Sendable (_ text: String, _ language: String) async -> Void
    var stop: @MainActor @Sendable () -> Void
}

extension SpeechSynthesizerClient: DependencyKey {
    nonisolated static let liveValue = SpeechSynthesizerClient(
        speak: { text, language in await TTSService.shared.speak(text, language: language) },
        stop: { TTSService.shared.stopSpeaking() }
    )
    nonisolated static let testValue = SpeechSynthesizerClient(speak: { _, _ in }, stop: {})
    nonisolated static var previewValue: SpeechSynthesizerClient { testValue }
}

extension DependencyValues {
    nonisolated var speechSynthesizer: SpeechSynthesizerClient {
        get { self[SpeechSynthesizerClient.self] }
        set { self[SpeechSynthesizerClient.self] = newValue }
    }
}
