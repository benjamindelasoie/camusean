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
    private var continuation: CheckedContinuation<[String], Never>?
    private var silenceTimer: Task<Void, Never>?

    // Pure string-level helper, extracted from listenForCandidates so it can be unit-tested
    // without driving the SFSpeechRecognizer.
    //
    // Behavior: trims whitespace, drops empty entries, dedupes case-insensitively (keeping
    // first occurrence and its original casing), caps the returned array at `max` entries.
    nonisolated static func extractDistinctTranscriptions(from strings: [String], max: Int = 3) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for s in strings {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
                if result.count >= max { break }
            }
        }
        return result
    }

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
                            let distinct = Self.extractDistinctTranscriptions(from: raw)
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

    // Backwards-compatibility shim while SessionViewModel still calls the single-word API.
    // Will be removed once T3 migrates the callsite to listenForCandidates.
    func listenForOneWord() async -> String? {
        await listenForCandidates().first
    }

    func reset() {
        continuation?.resume(returning: [])
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
