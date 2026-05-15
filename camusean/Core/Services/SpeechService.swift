import Speech
import AVFoundation
import Observation

@Observable
@MainActor
final class SpeechService {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var transcriptionContinuation: CheckedContinuation<String?, Never>?

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
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        return speechAuth && micAuth
    }

    func startListening() async {
        reset()
        do {
            try await AudioSessionManager.shared.activateForRecording()
        } catch {
            return
        }

        guard let recognizer, recognizer.isAvailable else { return }

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = false

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        try? engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    self.transcriptionContinuation?.resume(returning: text.isEmpty ? nil : text)
                    self.transcriptionContinuation = nil
                    return
                }
                if let error {
                    let code = (error as NSError).code
                    // 1110 = no speech detected, 1102 = cancelled — not errors worth propagating
                    if code == 1110 || code == 1102 {
                        self.transcriptionContinuation?.resume(returning: nil)
                    } else {
                        self.transcriptionContinuation?.resume(returning: nil)
                    }
                    self.transcriptionContinuation = nil
                }
            }
        }
    }

    // Stops audio capture and waits for the final transcription result.
    // Returns nil if nothing was recognized or on error.
    func finishAndTranscribe() async -> String? {
        return await withCheckedContinuation { continuation in
            transcriptionContinuation = continuation
            request?.endAudio()
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    func reset() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        transcriptionContinuation?.resume(returning: nil)
        transcriptionContinuation = nil
        request = nil
        task = nil
    }
}
