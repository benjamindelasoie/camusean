import Speech
import AVFoundation
import Observation

@Observable
@MainActor
final class SpeechService {
    // Live transcription shown while user is speaking
    var partialTranscription: String = ""

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var continuation: CheckedContinuation<String?, Never>?
    private var silenceTimer: Task<Void, Never>?

    func setLocale(_ identifier: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
    }

    func requestPermissions() async -> Bool {
        let speechAuth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let micAuth = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        return speechAuth && micAuth
    }

    // Listens until one complete utterance is detected (Apple fires isFinal after ~1s silence).
    // Returns the transcribed word/phrase, or nil on timeout, no speech, or cancellation.
    // Each call is self-contained: starts the engine, waits, stops the engine.
    func listenForOneWord() async -> String? {
        teardown()

        do { try AudioSessionManager.shared.activateForRecording() }
        catch { return nil }

        guard let recognizer, recognizer.isAvailable else { return nil }

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

        let result = await withCheckedContinuation { cont in
            self.continuation = cont
            self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.partialTranscription = result.bestTranscription.formattedString
                        self.restartSilenceTimer()
                        if result.isFinal {
                            self.silenceTimer?.cancel()
                            let text = result.bestTranscription.formattedString
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            self.partialTranscription = ""
                            self.continuation?.resume(returning: text.isEmpty ? nil : text)
                            self.continuation = nil
                        }
                    }
                    if error != nil {
                        self.silenceTimer?.cancel()
                        self.partialTranscription = ""
                        self.continuation?.resume(returning: nil)
                        self.continuation = nil
                    }
                }
            }
        }

        teardown()
        return result
    }

    func reset() {
        continuation?.resume(returning: nil)
        continuation = nil
        teardown()
        partialTranscription = ""
    }

    private func restartSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.0))
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
