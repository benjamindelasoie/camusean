import Speech
import AVFoundation
import Observation

// SFSpeechRecognizer-based backend (iOS 18–25, and the fallback whenever the iOS 26
// DictationTranscriber path isn't available). Unchanged behavior — this is the speech
// engine the app has always shipped; it now just satisfies the SpeechRecognizing seam.
@Observable
@MainActor
final class LegacySpeechRecognizer: SpeechRecognizing {
    // Live transcription shown while user is speaking
    var partialTranscription: String = ""

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var continuation: CheckedContinuation<[String], Never>?
    private var silenceTimer: Task<Void, Never>?

    // Constructing the recognizer touches no main-actor state, so the factory (and the
    // swift-dependencies live value) can build it from a nonisolated context.
    nonisolated init() {}

    func setLocale(_ identifier: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
    }

    func requestPermissions() async -> Bool {
        // Delegated to a nonisolated helper so the TCC background-queue callbacks don't trip
        // the Swift 6 main-actor executor assertion (see SpeechRecognition.requestMicAndSpeechAuthorization).
        await SpeechRecognition.requestMicAndSpeechAuthorization()
    }

    // Listens until one complete utterance is detected (Apple fires isFinal after ~1s silence).
    // Returns up to 3 distinct candidate transcriptions from Apple's ASR, or an empty array
    // on timeout / no speech / cancellation. Each call is self-contained: starts the engine,
    // waits, stops the engine.
    func listenForCandidates() async -> [String] {
        teardown()

        do { try AudioSessionManager.shared.activateForRecording() }
        catch { return [] }

        guard let recognizer, recognizer.isAvailable else { return [] }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        self.request = req

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard buffer.frameLength > 0 else { return }
            self?.request?.append(buffer)
        }
        engine.prepare()
        try? engine.start()

        let candidates = await withCheckedContinuation { cont in
            self.continuation = cont
            self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.partialTranscription = result.bestTranscription.formattedString
                        self.restartSilenceTimer()
                        if result.isFinal {
                            self.silenceTimer?.cancel()
                            let raw = result.transcriptions.map { $0.formattedString }
                            let distinct = SpeechRecognition.extractDistinctTranscriptions(from: raw)
                            self.partialTranscription = ""
                            self.continuation?.resume(returning: distinct)
                            self.continuation = nil
                        }
                    }
                    if error != nil {
                        self.silenceTimer?.cancel()
                        self.partialTranscription = ""
                        self.continuation?.resume(returning: [])
                        self.continuation = nil
                    }
                }
            }
        }

        teardown()
        return candidates
    }

    func reset() {
        continuation?.resume(returning: [])
        continuation = nil
        teardown()
        partialTranscription = ""
    }

    // How long the user must stay silent after speaking before we finalize the utterance.
    // These are single foreign words, so we can endpoint aggressively — every 100ms here is
    // 100ms shaved off every lookup. Tunable; confirm the feel on-device before lowering further.
    private let silenceTimeout: Duration = .seconds(0.6)

    private func restartSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: self?.silenceTimeout ?? .seconds(0.6))
            guard !Task.isCancelled else { return }
            self?.endAudioInput()
        }
    }

    private func endAudioInput() {
        request?.endAudio()
    }

    private func teardown() {
        silenceTimer?.cancel()
        silenceTimer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
    }
}
