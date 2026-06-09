import Dependencies
import Observation

// Registers the speech-recognition seam with swift-dependencies so call sites resolve it
// via `@Dependency(\.speechRecognizer)` instead of constructing a backend directly. This
// is the consistent DI seam the rest of the app's services (Anthropic, TTS, Keychain) can
// adopt over time; today it makes the speech engine trivially swappable in tests/previews.
//
// `liveValue` is the OS-appropriate backend (DictationTranscriber on iOS 26+, else
// SFSpeechRecognizer). `testValue`/`previewValue` are inert so tests and previews never
// touch the microphone unless they explicitly opt in by overriding the dependency.
//
// The getters are `nonisolated` to satisfy swift-dependencies' nonisolated requirements
// (this module otherwise defaults to MainActor isolation); the backends construct without
// main-actor state, so that's safe.
private enum SpeechRecognizerKey: DependencyKey {
    nonisolated static var liveValue: any SpeechRecognizing { SpeechRecognition.make() }
    nonisolated static var testValue: any SpeechRecognizing { NoopSpeechRecognizer() }
    nonisolated static var previewValue: any SpeechRecognizing { NoopSpeechRecognizer() }
}

extension DependencyValues {
    nonisolated var speechRecognizer: any SpeechRecognizing {
        get { self[SpeechRecognizerKey.self] }
        set { self[SpeechRecognizerKey.self] = newValue }
    }
}

// Inert backend used in tests and SwiftUI previews — no microphone, no recognition.
// Tests that need recognized words override the dependency with their own double:
//   withDependencies { $0.speechRecognizer = StubRecognizer(candidates: ["bonjour"]) }
//     operation: { /* drive the view model */ }
@Observable
@MainActor
final class NoopSpeechRecognizer: SpeechRecognizing {
    var partialTranscription: String = ""
    let backendName = "Noop"
    let localeSupported: Bool? = nil
    let lastErrorMessage: String? = nil
    nonisolated init() {}
    func setLocale(_ identifier: String) {}
    func requestPermissions() async -> Bool { false }
    func listenForCandidates() async -> [String] { [] }
    func reset() {}
}
