import AVFoundation

// Speech output. One synthesizer, shared by the reading session and the review deck.
//
// speak() is INTERRUPT-AND-REPLACE. A second call cuts the first one off and its `await`
// returns immediately. This matters because there is exactly one continuation slot: the
// original implementation overwrote it, so the first caller's `await` never resumed and
// that task hung for the life of the app. Latent while only SessionViewModel called it
// (sequentially, one flow); reachable the moment a flashcard word became tappable.
//
//   speak(A) ──▶ continuation = cA, currentUtterance = A ──▶ synthesizer.speak(A)
//   speak(B) ──▶ cA.resume()          ← A's caller unblocks, does not hang
//                currentUtterance = nil
//                stopSpeaking          ← queues didCancel(A) on the main actor
//                continuation = cB, currentUtterance = B
//   didCancel(A) ──▶ A !== currentUtterance (now B) ──▶ ignored
//   didFinish(B) ──▶ B === currentUtterance ──▶ cB.resume()
//
// The identity check is load-bearing: without it the queued didCancel for the *previous*
// utterance resumes the *new* caller's continuation, so B's await returns while B is
// still speaking.
@MainActor
final class TTSService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = TTSService()
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    /// The utterance the stored continuation belongs to. Delegate callbacks for any other
    /// utterance are stale and must be ignored.
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

    // True if an Enhanced or Premium voice is installed for `language` (matches by 2-letter prefix).
    // Without one, AVSpeechSynthesizer falls back to the compact default and sounds robotic.
    // Users must download enhanced voices in iOS Settings -> Accessibility -> Spoken Content.
    static func hasEnhancedVoice(forLanguagePrefix prefix: String) -> Bool {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .contains { $0.quality == .enhanced || $0.quality == .premium }
    }

    /// Stops any in-flight speech and unblocks its caller. Safe to call when nothing is
    /// speaking. Callers that own the audio session (a review card leaving the screen, a
    /// session ending) should use this rather than letting speech outlive its context.
    func stopSpeaking() {
        continuation?.resume()
        continuation = nil
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Resumes the waiter only if the callback belongs to the utterance it is waiting on.
    ///
    /// Compared by `ObjectIdentifier` rather than the utterance itself: `AVSpeechUtterance`
    /// is not `Sendable`, so under Swift 6 it cannot cross from the nonisolated delegate to
    /// the main actor. The identifier is a plain value and can. `currentUtterance` keeps a
    /// strong reference so the address cannot be recycled by a later utterance.
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
