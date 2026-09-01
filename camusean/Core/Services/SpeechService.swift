import Speech
import AVFoundation
import Observation

// SFSpeechRecognizer backend (iOS 18–25, and the fallback whenever the iOS 26
// DictationTranscriber path isn't available).
@Observable
@MainActor
final class LegacySpeechRecognizer: SpeechRecognizing {
    var partialTranscription: String = ""

    // SFSpeechRecognizer supports all system locales, so `localeSupported` is always true here.
    var backendName: String {
        "Legacy · SFSpeechRecognizer (\(usedOnDeviceRecognition ? "on-device" : "server"))"
    }
    let localeSupported: Bool? = true
    private(set) var lastErrorMessage: String?

    /// Whether the last `listenForCandidates()` actually ran on-device — see `listenForCandidates`.
    private(set) var usedOnDeviceRecognition = false

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var continuation: CheckedContinuation<[String], Never>?
    private var silenceTimer: Task<Void, Never>?

    // Constructing the recognizer touches no main-actor state, so a nonisolated context can build it.
    nonisolated init() {}

    func setLocale(_ identifier: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
    }

    func requestPermissions() async -> Bool {
        // Nonisolated helper so the TCC background-queue callbacks don't trip the Swift 6 main-actor
        // executor assertion (see SpeechRecognition.requestMicAndSpeechAuthorization).
        await SpeechRecognition.requestMicAndSpeechAuthorization()
    }

    // Apple fires isFinal after ~1s silence. Each call is self-contained: starts the engine, waits,
    // stops the engine.
    func listenForCandidates() async -> [String] {
        teardown()
        lastErrorMessage = nil

        do { try AudioSessionManager.shared.activateForRecording() }
        catch {
            lastErrorMessage = "audio session: \(error.localizedDescription)"
            return []
        }

        guard let recognizer, recognizer.isAvailable else {
            lastErrorMessage = "recognizer unavailable"
            return []
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true

        // Left unset this defaults to false, and SFSpeechRecognizer may stream mic audio to Apple's
        // servers. Gated on `supportsOnDeviceRecognition` rather than forced to `true`: forcing it
        // makes recognition fail outright for a locale whose on-device assets aren't installed. The
        // flag is per-locale and flips to true once iOS downloads a language's assets, so the same
        // user can legitimately see both modes over time.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        usedOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

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
                    if let error {
                        self.lastErrorMessage = error.localizedDescription
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

    // Single foreign words, so we can endpoint aggressively — every 100ms here is 100ms off every
    // lookup. Confirm the feel on-device before lowering further.
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
