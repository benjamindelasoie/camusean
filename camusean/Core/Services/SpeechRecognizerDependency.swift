import Dependencies
import Observation

// swift-dependencies seam for speech-to-text: call sites resolve `@Dependency(\.speechRecognizer)`
// instead of constructing a backend. `liveValue` is the OS-appropriate recognizer; test/preview are
// inert so nothing touches the mic unless overridden. Getters are `nonisolated` to meet
// swift-dependencies' requirements (the module otherwise defaults to MainActor).
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

// Inert backend for tests and previews — no mic. Override to supply candidates:
//   withDependencies { $0.speechRecognizer = StubRecognizer(candidates: ["bonjour"]) }
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
