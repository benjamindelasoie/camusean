import AVFoundation

// The single owner of `AVAudioSession`.
//
// iOS gives the app one shared audio configuration. Before this existed as a real owner,
// three places reconfigured it by hand — the two speech recognizers claimed `.playAndRecord`
// when they started listening, and `SessionViewModel` flipped to `.playback` and back around
// every spoken word. That worked only because the reading session was the sole audio feature.
// The moment a second one appears (a tappable word on a review card), a `.playback` switch
// lands on a session whose audio engine is mid-capture and recognition stops with no error.
//
// The fix is not "don't let the second feature play." It is to give the session an owner and
// a primitive that expresses what everyone actually wants:
//
//     performPlayback { await tts.speak(...) }
//
//   mode == .recording ──▶ suspend capture ──▶ play ──▶ resume capture
//   mode == .idle      ──▶ activate playback ──▶ play ──▶ deactivate
//
// Callers no longer decide categories. They declare intent and the manager restores whatever
// was running before. This is also what keeps the microphone from transcribing the app's own
// voice: capture is genuinely suspended for the duration of playback, not merely talked over.
@MainActor
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    enum Mode: String {
        case idle
        case recording
        case playback
    }

    /// What the shared session is configured for right now. Read-only to callers — the whole
    /// point is that nobody outside this type sets a category.
    private(set) var mode: Mode = .idle

    /// True while something owns the microphone. Consulted by UI that needs to know whether a
    /// reading session is live.
    var isRecording: Bool { mode == .recording }

    /// Invoked when the system interrupts audio (a phone call, Siri). The reading session
    /// subscribes so it can end cleanly instead of appearing to listen to a dead engine.
    var onInterruption: (() -> Void)?

    private init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            // The observer block is nonisolated; hop before touching actor-isolated state.
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                guard let self, let raw, raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                self.mode = .idle
                self.onInterruption?()
            }
        }
    }

    // MARK: - Recording

    /// Claim the microphone. Idempotent: the recognizers call this at the top of every listen
    /// cycle, so it must be cheap and safe to repeat.
    func activateForRecording() throws {
        guard mode != .recording else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        mode = .recording
    }

    // MARK: - Playback

    /// Run `body` with the session configured for playback, then restore the previous mode.
    ///
    /// This is the primitive every playback path should use. Speaking from the review deck
    /// while a reading session is live is safe through this call and unsafe without it: it
    /// suspends capture for the duration and hands the microphone back afterwards.
    func performPlayback(_ body: () async -> Void) async {
        let previous = mode
        try? activateForPlayback()
        await body()
        switch previous {
        case .recording:
            try? activateForRecording()
        case .idle:
            deactivate()
        case .playback:
            break
        }
    }

    /// Prefer `performPlayback`. Exposed for the reading session's lookup flow, which holds
    /// playback open across an intervening network call and cannot wrap it in one closure.
    func activateForPlayback() throws {
        guard mode != .playback else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        mode = .playback
    }

    // MARK: - Teardown

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        mode = .idle
    }
}
