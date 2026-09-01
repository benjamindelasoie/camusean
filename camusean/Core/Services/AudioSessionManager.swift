import AVFoundation

// The single owner of `AVAudioSession`. iOS gives the app one shared audio configuration, so
// letting recognizers and the lookup flow set categories by hand meant a `.playback` switch
// could land mid-capture and silently stop recognition. Callers declare intent instead:
//
//     performPlayback { await tts.speak(...) }
//
//   mode == .recording ──▶ suspend capture ──▶ play ──▶ resume capture
//   mode == .idle      ──▶ activate playback ──▶ play ──▶ deactivate
//
// Capture is genuinely suspended for playback, so the mic never transcribes the app's own voice.
@MainActor
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    enum Mode: String {
        case idle
        case recording
        case playback
    }

    // Every transition is traced because audio bugs are device-only and silent: a clobbered
    // category stops recognition with no error. Plain `print` (not `Logger`) so it reaches
    // stdout without root, and not `#if DEBUG` so a TestFlight "it stopped hearing me" stays
    // diagnosable.

    /// What the shared session is configured for. Read-only — nobody outside this type sets a category.
    private(set) var mode: Mode = .idle {
        didSet {
            guard oldValue != mode else { return }
            print("[audio] mode \(oldValue.rawValue) -> \(mode.rawValue)")
        }
    }

    var isRecording: Bool { mode == .recording }

    /// Fires when the system interrupts audio (call, Siri) so the reading session can end cleanly.
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
                print("[audio] interruption began — ending audio")
                self.mode = .idle
                self.onInterruption?()
            }
        }
    }

    // MARK: - Recording

    /// Claim the microphone. Idempotent — called at the top of every listen cycle.
    func activateForRecording() throws {
        guard mode != .recording else {
            print("[audio] activateForRecording: already recording, no-op")
            return
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        mode = .recording
    }

    // MARK: - Playback

    /// Run `body` with playback active, then restore the previous mode. The primitive every
    /// playback path should use: it suspends capture for the duration, so speaking from the
    /// review deck while a reading session is live is safe through this call and unsafe without it.
    func performPlayback(_ body: () async -> Void) async {
        let previous = mode
        print("[audio] performPlayback begin (was \(previous.rawValue))")
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
        print("[audio] performPlayback end (restored \(mode.rawValue))")
    }

    /// Prefer `performPlayback`. For the lookup flow, which holds playback open across a network call.
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
