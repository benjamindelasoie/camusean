import Speech
import AVFoundation
import Observation
import os

// iOS 26+ on-device speech backend (SpeechAnalyzer). Uses `DictationTranscriber`, which reuses
// the system dictation models — no large per-locale download, unlike `SpeechTranscriber`. The
// contract mirrors `LegacySpeechRecognizer` so `SessionViewModel` stays backend-agnostic.
@available(iOS 26, *)
@Observable
@MainActor
final class DictationSpeechRecognizer: SpeechRecognizing {
    var partialTranscription: String = ""

    let backendName = "Dictation · SpeechAnalyzer (iOS 26)"
    private(set) var localeSupported: Bool?
    private(set) var lastErrorMessage: String?

    private var localeIdentifier: String = "en-US"

    private let engine = AVAudioEngine()
    private let converter = BufferConverter()

    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<[String], Never>?
    private var silenceTimer: Task<Void, Never>?
    private var candidates: [String] = []

    // Match the legacy path's aggressive endpointing — these are single foreign words.
    private let silenceTimeout: Duration = .seconds(0.6)

    // No main-actor state at init, so the factory / live value can build it nonisolated.
    nonisolated init() {}

    func setLocale(_ identifier: String) {
        localeIdentifier = identifier
    }

    // Still requests Speech authorization (despite being on-device) so behavior and the Settings
    // copy match the legacy backend.
    func requestPermissions() async -> Bool {
        // Nonisolated helper so the TCC background-queue callbacks don't trip the Swift 6
        // main-actor executor assertion (see SpeechRecognition.requestMicAndSpeechAuthorization).
        await SpeechRecognition.requestMicAndSpeechAuthorization()
    }

    // Listens for one utterance, returning up to 3 distinct candidates (final text + alternatives)
    // or [] on no-speech / model-unavailable / cancellation. Builds the analyzer, streams the mic,
    // finalizes, tears down.
    func listenForCandidates() async -> [String] {
        teardown()
        candidates = []
        partialTranscription = ""
        lastErrorMessage = nil

        do { try AudioSessionManager.shared.activateForRecording() }
        catch {
            lastErrorMessage = "audio session: \(error.localizedDescription)"
            return []
        }

        let locale = Locale(identifier: localeIdentifier)
        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        do {
            try await ensureModel(for: transcriber, locale: locale)
        } catch {
            // Rare-locale edge (French, the default, is a system dictation language). Returning []
            // keeps the session alive; the loop waits for the next utterance.
            print("[Dictation] model/locale unavailable for \(localeIdentifier): \(error)")
            lastErrorMessage = "model/locale unavailable for \(localeIdentifier): \(error.localizedDescription)"
            teardown()
            return []
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            teardown()
            return []
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation

        return await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            self.continuation = cont

            // Volatile results drive the live partial + silence timer; the final result is the candidates.
            resultsTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await result in transcriber.results {
                        if result.isFinal {
                            var raw = [String(result.text.characters)]
                            raw.append(contentsOf: result.alternatives.map { String($0.characters) })
                            self.candidates = SpeechRecognition.extractDistinctTranscriptions(from: raw)
                        } else {
                            self.partialTranscription = String(result.text.characters)
                            self.restartSilenceTimer()
                        }
                    }
                    self.finish(with: self.candidates)
                } catch {
                    self.finish(with: [])
                }
            }

            Task { [weak self] in
                do { try await analyzer.start(inputSequence: inputStream) }
                catch { self?.finish(with: []) }
            }

            let input = engine.inputNode
            let tapFormat = input.outputFormat(forBus: 0)
            installMicTap(
                on: input,
                tapFormat: tapFormat,
                analyzerFormat: format,
                converter: self.converter,
                continuation: inputContinuation
            )
            engine.prepare()
            do { try engine.start() }
            catch { finish(with: []) }
        }
    }

    // `nonisolated` is load-bearing: AVFoundation runs the tap block on its realtime queue, and a
    // @MainActor-isolated block (the default inside this class) would assert it's on the main
    // executor → EXC_BREAKPOINT on the first buffer. This method's block touches only its passed-in
    // locals (a nonisolated BufferConverter + the Sendable continuation), never main-actor state.
    nonisolated private func installMicTap(
        on input: AVAudioInputNode,
        tapFormat: AVAudioFormat,
        analyzerFormat: AVAudioFormat,
        converter: BufferConverter,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { buffer, _ in
            guard buffer.frameLength > 0 else { return }
            guard let converted = try? converter.convertBuffer(buffer, to: analyzerFormat) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    func reset() {
        continuation?.resume(returning: [])
        continuation = nil
        teardown()
        partialTranscription = ""
    }

    // MARK: - Endpointing

    private func restartSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: self?.silenceTimeout ?? .seconds(0.6))
            guard !Task.isCancelled else { return }
            await self?.finalizeInput()
        }
    }

    // Endpoint reached: stop feeding audio and ask the analyzer to flush a final result.
    private func finalizeInput() async {
        inputContinuation?.finish()
        inputContinuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
    }

    private func finish(with candidates: [String]) {
        guard let cont = continuation else { return }
        continuation = nil
        partialTranscription = ""
        cont.resume(returning: candidates)
        teardown()
    }

    private func teardown() {
        silenceTimer?.cancel(); silenceTimer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish(); inputContinuation = nil
        resultsTask?.cancel(); resultsTask = nil
        analyzer = nil
        transcriber = nil
    }

    // MARK: - Model / locale assets

    private func ensureModel(for transcriber: DictationTranscriber, locale: Locale) async throws {
        guard await isSupported(locale) else { throw RecognizerError.localeNotSupported }
        // Usually a no-op for dictation languages — the assets ship with the keyboard.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let reserved = await AssetInventory.reservedLocales
        if !reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            try await AssetInventory.reserve(locale: locale)
        }
    }

    private func isSupported(_ locale: Locale) async -> Bool {
        let supported = await DictationTranscriber.supportedLocales
        let ok = supported.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        // Cache so the debug overlay reads it synchronously — distinct from a later download failure.
        localeSupported = ok
        return ok
    }

    enum RecognizerError: Error { case localeNotSupported }
}

// Converts mic buffers to the analyzer's format. Ported from FluidInference/swift-scribe.
// `nonisolated`: runs on AVFoundation's realtime audio thread from the tap block, never the main
// actor — leaving it MainActor-isolated is what tripped the Swift 6 executor assertion.
@available(iOS 26, *)
nonisolated private final class BufferConverter {
    enum Error: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none  // avoid timestamp drift from priming the first samples
        }

        guard let converter else { throw Error.failedToCreateConverter }

        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        guard let conversionBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frameCapacity) else {
            throw Error.failedToCreateConversionBuffer
        }

        var nsError: NSError?
        let bufferProcessedLock = OSAllocatedUnfairLock(initialState: false)

        // The @Sendable input block must return the non-Sendable source buffer. It runs
        // synchronously on this thread before convert() returns, so the hand-off is safe;
        // nonisolated(unsafe) states that and silences the framework-gap warning.
        nonisolated(unsafe) let inputBuffer = buffer
        let status = converter.convert(to: conversionBuffer, error: &nsError) { _, inputStatusPointer in
            let wasProcessed = bufferProcessedLock.withLock { bufferProcessed -> Bool in
                let wasProcessed = bufferProcessed
                bufferProcessed = true
                return wasProcessed
            }
            inputStatusPointer.pointee = wasProcessed ? .noDataNow : .haveData
            return wasProcessed ? nil : inputBuffer
        }

        guard status != .error else { throw Error.conversionFailed(nsError) }
        return conversionBuffer
    }
}
