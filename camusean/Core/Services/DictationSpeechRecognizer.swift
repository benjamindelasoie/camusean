import Speech
import AVFoundation
import Observation
import os

// iOS 26+ speech backend built on Apple's on-device SpeechAnalyzer pipeline.
//
// Uses `DictationTranscriber` — the short-utterance module that reuses the system
// dictation models (no large per-locale model download, unlike `SpeechTranscriber`),
// which is exactly the right fit for single-word lookups. It runs fully on-device,
// is more private than the legacy server-capable path, and Apple reports it ~2× faster
// than Whisper Large-v3-Turbo.
//
// The contract mirrors `LegacySpeechRecognizer` so `SessionViewModel` stays backend-
// agnostic: set a locale, listen for one utterance, get up to 3 candidate strings,
// with a live `partialTranscription` while the user speaks. Endpointing matches the
// legacy path — finalize after `silenceTimeout` of no new volatile results.
@available(iOS 26, *)
@Observable
@MainActor
final class DictationSpeechRecognizer: SpeechRecognizing {
    var partialTranscription: String = ""

    // Diagnostics surfaced by the session debug overlay.
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

    // Constructing the recognizer touches no main-actor state, so the factory (and the
    // swift-dependencies live value) can build it from a nonisolated context.
    nonisolated init() {}

    func setLocale(_ identifier: String) {
        localeIdentifier = identifier
    }

    // Permission model is unchanged from the legacy path: microphone + Speech
    // authorization. (SpeechAnalyzer is fully on-device, but we keep requesting the
    // same Speech authorization the app already asks for so behavior is identical
    // across backends and the Settings copy stays accurate.)
    func requestPermissions() async -> Bool {
        // Delegated to a nonisolated helper so the TCC background-queue callbacks don't trip
        // the Swift 6 main-actor executor assertion (see SpeechRecognition.requestMicAndSpeechAuthorization).
        await SpeechRecognition.requestMicAndSpeechAuthorization()
    }

    // Listens until one complete utterance is detected. Returns up to 3 distinct
    // candidate transcriptions (the final result's text plus its alternatives), or an
    // empty array on no-speech / model-unavailable / cancellation. Self-contained:
    // builds the analyzer, streams the mic, finalizes, tears down.
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
            // The default source language (French) is a system dictation language, so this
            // is the rare-locale edge. Returning [] keeps the session alive; the loop simply
            // waits for the next utterance. (A per-locale fallback to the legacy recognizer
            // would close this gap — see the note in the research write-up.)
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

            // Reader: pull transcription results until the stream completes (after finalize).
            // Volatile results drive the live partial display + the silence timer; the final
            // result yields our candidate list.
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

            // Drive the analyzer over the mic input stream.
            Task { [weak self] in
                do { try await analyzer.start(inputSequence: inputStream) }
                catch { self?.finish(with: []) }
            }

            // Mic tap: convert each buffer to the analyzer's format and feed the input stream.
            // Installed via a nonisolated helper so the realtime audio-thread callback carries
            // no @MainActor isolation — otherwise Swift 6 traps it with a main-executor assertion
            // (EXC_BREAKPOINT) the instant the first buffer arrives off-main. See installMicTap.
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

    // Installs the AVAudioEngine mic tap. `nonisolated` is load-bearing: AVFoundation invokes
    // the tap block on its realtime background queue, and a @MainActor-isolated block (which is
    // what the compiler infers inside this @MainActor class) would assert it's on the main
    // executor before running — tripping `dispatch_assert_queue` → EXC_BREAKPOINT the moment the
    // first buffer arrives. Defining the block in this nonisolated method strips that isolation.
    // The block only touches its passed-in locals (a nonisolated BufferConverter + the Sendable
    // continuation), never main-actor state.
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
    // The results stream then delivers the final transcription and completes, which
    // resolves listenForCandidates() via the reader task.
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
        // Install the on-device assets if the system doesn't already have them. For
        // dictation languages this is usually a no-op (the assets ship with the keyboard).
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
        // Cache the real signal (locale present in the supported set) so the debug overlay
        // can read it synchronously — kept distinct from a later asset-download failure.
        localeSupported = ok
        return ok
    }

    enum RecognizerError: Error { case localeNotSupported }
}

// Converts mic buffers into the sample rate/format the analyzer expects.
// Ported from FluidInference/swift-scribe (the reference iOS 26 SpeechAnalyzer app).
//
// `nonisolated` (opting out of the module's MainActor default): this runs on AVFoundation's
// realtime audio thread from the mic-tap block, never on the main actor. Leaving it
// MainActor-isolated is what made the tap callback trip a Swift 6 executor assertion.
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

        // AVAudioConverter's input block is @Sendable, but the API requires returning the
        // (non-Sendable) source buffer from it. The block is invoked synchronously on this
        // same thread before convert() returns, so handing the buffer across is safe —
        // nonisolated(unsafe) states that explicitly and silences the framework-gap warning.
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
