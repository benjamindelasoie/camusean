import SwiftUI
import SwiftData

struct ReadingSessionView: View {
    @State private var vm = SessionViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL

    @Query private var allWords: [Word]

    // nil selectedBook = a free session; the selector defaults to the most recent book.
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]
    @State private var selectedBook: Book?
    @State private var didDefaultBook = false
    @State private var showAddBook = false

    @State private var showVoiceOnboarding = false

    // Not #if DEBUG on purpose — must stay available to diagnose Release/TestFlight builds.
    @AppStorage("showSessionDebugOverlay") private var showSessionDebugOverlay = false

    #if DEBUG
    // Fires the QA injection once per launch, not on every onAppear (tab re-entry re-fires it).
    @State private var qaInjectionFired = false
    #endif

    private static let voicePromptShownKey = "voicePromptShown"

    // @ScaledMetric, not fixed sizes: fixed point sizes ignore the reader's text-size setting,
    // which left the app title smaller than the body copy at accessibility sizes.
    @ScaledMetric(relativeTo: .largeTitle) private var heroTitleSize: CGFloat = 38
    @ScaledMetric(relativeTo: .largeTitle) private var resultWordSize: CGFloat = 40
    @ScaledMetric(relativeTo: .title) private var transcriptionSize: CGFloat = 30

    // A single `.sheet(item:)` presenter: two `.sheet(isPresented:)` on one view is a SwiftUI
    // conflict that eats taps in the presented sheet.
    private enum ActiveSheet: Identifiable {
        case summary
        case voiceOnboarding
        case addBook
        var id: Self { self }
    }

    // Summary wins if both triggers are set; clearing resets both so interactive dismissal
    // can't strand a flag.
    private var activeSheet: Binding<ActiveSheet?> {
        Binding(
            get: {
                if vm.showSummary { return .summary }
                if showVoiceOnboarding { return .voiceOnboarding }
                if showAddBook { return .addBook }
                return nil
            },
            set: { newValue in
                if newValue == nil {
                    vm.showSummary = false
                    showVoiceOnboarding = false
                    showAddBook = false
                }
            }
        )
    }

    var body: some View {
        ZStack {
            if !vm.isSessionActive {
                startScreen
                    .transition(reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity,
                            removal: .scale(scale: 0.96).combined(with: .opacity)
                        ))
            } else {
                sessionScreen
                    .transition(reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .scale(scale: 1.03).combined(with: .opacity),
                            removal: .opacity
                        ))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: vm.isSessionActive)
        .sheet(item: activeSheet) { sheet in
            switch sheet {
            case .summary:
                summarySheet
            case .voiceOnboarding:
                VoiceSetupSheet(languages: VoiceSetup.relevantLanguages()) {
                    UserDefaults.standard.set(true, forKey: Self.voicePromptShownKey)
                    showVoiceOnboarding = false
                }
            case .addBook:
                AddBookView { book in
                    selectedBook = book
                    showAddBook = false
                }
            }
        }
        .onAppear {
            vm.modelContext = modelContext
            // Default to the most recent book only once, so a free choice survives tab returns.
            if !didDefaultBook {
                selectedBook = books.first
                didDefaultBook = true
            }
            evaluateVoiceOnboarding()
            #if DEBUG
            maybeRunQAInjection()
            #endif
        }
        // Drop a selected book that vanished from the store, so no session or saved word tags a
        // deleted book and the selector can't show a phantom title.
        .onChange(of: books.map(\.persistentModelID)) { _, ids in
            if let selected = selectedBook, !ids.contains(selected.persistentModelID) {
                selectedBook = nil
            }
        }
    }

    private func handleMicTap() {
        switch vm.phase {
        case .processing, .result:
            vm.cancelCurrentLookup()
        case .idle, .listening, .error:
            break
        }
    }

    #if DEBUG
    // QA mic-bypass: `-qaWord <word>` at launch injects that word into the retrieval flow
    // (Haiku → save → TTS) with no microphone. Lives in NSUserDefaults' volatile argument
    // domain (never persisted), set per launch via:
    //   xcrun devicectl device process launch ... com.bdelasoie.camusean -qaWord bonjour
    private func maybeRunQAInjection() {
        guard !qaInjectionFired,
              let word = UserDefaults.standard.string(forKey: "qaWord"),
              !word.isEmpty else { return }
        qaInjectionFired = true
        Task { await vm.debugSimulateHeardWord(word) }
    }
    #endif

    // MARK: - Voice onboarding

    // TODO: migrate this one-time prompt to TipKit when adding a second tip. See TODOS.md.
    private func evaluateVoiceOnboarding() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.voicePromptShownKey) else { return }

        if VoiceSetup.isAnyVoiceMissing() {
            showVoiceOnboarding = true
        } else {
            // Nothing to download; never auto-prompt again.
            defaults.set(true, forKey: Self.voicePromptShownKey)
        }
    }

    // Gates the one-time gesture hint off the word store — no separate onboarding flag needed.
    private var isFirstTime: Bool { allWords.isEmpty }

    // "Learned" = scheduled with interval >= 6 days, created this week.
    private var learnedThisWeekCount: Int {
        let now = Date()
        let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return allWords.filter { word in
            word.nextReviewDate != nil
                && word.interval >= 6
                && word.timestamp >= startOfWeek
        }.count
    }

    // MARK: - Start Screen

    private var startScreen: some View {
        // Scrolls only when it must: at accessibility text sizes the pitch + CTA overflow a
        // fixed VStack. `.basedOnSize` keeps the normal case static.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    heroMark
                    Spacer().frame(height: 32)
                    heroText
                    // Capped so surplus height rises above the hero instead of opening a dead
                    // band mid-screen (unbounded Spacers split the slack and left a visible gap).
                    Spacer().frame(minHeight: 32, maxHeight: 96)
                    bookSelector
                    Spacer().frame(height: 16)
                    startCTA
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // Books live here, where a session begins, rather than in a 4th tab.
    private var bookSelector: some View {
        Menu {
            Button { selectedBook = nil } label: {
                Label("Free reading", systemImage: selectedBook == nil ? "checkmark" : "book.closed")
            }
            if !books.isEmpty {
                Divider()
                ForEach(books) { book in
                    Button { selectedBook = book } label: {
                        Label(book.title,
                              systemImage: book.persistentModelID == selectedBook?.persistentModelID ? "checkmark" : "book")
                    }
                }
            }
            Divider()
            Button { showAddBook = true } label: {
                Label("Add a book…", systemImage: "barcode.viewfinder")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedBook == nil ? "book.closed" : "book.fill")
                Text(selectedBook?.title ?? "Free reading")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.camuseanText)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.camusean.opacity(0.12)))
        }
    }

    private var heroMark: some View {
        // Decorative, so it shrinks at accessibility sizes to yield room rather than push the
        // words and button off the fold.
        let scale: CGFloat = typeSize.isAccessibilitySize ? 0.6 : 1
        return ZStack {
            Circle()
                .fill(Color.camusean.opacity(0.07))
                .frame(width: 156 * scale, height: 156 * scale)
            Circle()
                .fill(Color.camusean.opacity(0.11))
                .frame(width: 120 * scale, height: 120 * scale)
            Image(systemName: "book.pages")
                .font(.system(size: 52 * scale, weight: .light))
                .foregroundStyle(Color.camusean)
        }
        .accessibilityHidden(true)
    }

    private var heroText: some View {
        VStack(spacing: 12) {
            Text("Camusean")
                .font(.system(size: heroTitleSize, weight: .bold, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // Never truncated: at accessibility sizes the second line used to vanish, taking
            // half the pitch with it.
            Text("Say a word you don't know.\nHear its meaning. Keep reading.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if case .error(let msg) = vm.phase {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
        }
    }

    private var startCTA: some View {
        VStack(spacing: 12) {
            Button {
                vm.activeBook = selectedBook
                Task { await vm.startSession() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                    // Primary CTA: wraps rather than truncating to "Begin Re…" at large sizes.
                    Text("Begin Reading")
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.camusean)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            if vm.permissionDenied {
                // iOS won't re-prompt after a denial — give a direct route to flip it on.
                Button {
                    if let url = URL(string: vm.settingsURLString) { openURL(url) }
                } label: {
                    Text("Open Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.camuseanText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
            } else {
                Text("Requires microphone & speech recognition")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Session Screen

    private var sessionScreen: some View {
        VStack(spacing: 0) {
            sessionHeader
                .padding(.horizontal, 28)
                .padding(.top, 20)

            Spacer()

            statusDisplay
                .padding(.horizontal, 36)

            Spacer()

            OrganicMicView(
                isListening: isListening,
                isProcessing: isProcessing,
                onTap: handleMicTap
            )

            Spacer()

            // The only way out of a session — must stay legible and meet the 44pt hit target.
            Button("End session") { vm.endSession() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .padding(.bottom, 32)
        }
        .safeAreaInset(edge: .top) {
            if showSessionDebugOverlay { debugOverlay }
        }
    }

    // MARK: - Debug Overlay

    // Recognition diagnostics (gated by the Settings → Developer toggle). The `candidates: —`
    // line is the silent-degrade tell when the recognizer hears nothing.
    private var debugOverlay: some View {
        let supported: String = {
            switch vm.debugLocaleSupported {
            case .some(true): return "yes"
            case .some(false): return "no"
            case .none: return "unknown"
            }
        }()
        return VStack(alignment: .leading, spacing: 2) {
            debugRow("backend", vm.debugBackendName.isEmpty ? "—" : vm.debugBackendName)
            debugRow("locale", "\(vm.sourceLocale) · supported: \(supported)")
            debugRow("phase", vm.debugPhaseLabel)
            debugRow("partial", vm.partialTranscription.isEmpty ? "—" : vm.partialTranscription)
            debugRow("candidates", vm.lastCandidates.isEmpty ? "—" : vm.lastCandidates.joined(separator: " | "))
            debugRow("error", vm.debugLastError ?? "—", tint: vm.debugLastError == nil ? nil : .red)
            debugRow("counts", "lookups \(vm.lookupCount) · rejected \(vm.recentlyRejected.count)")
        }
        .font(.system(.caption2, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
    }

    private func debugRow(_ key: String, _ value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(key)
                .foregroundStyle(Color.camusean)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .foregroundStyle(tint ?? .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CAMUSEAN")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(.secondary)
                    .kerning(2)
                Spacer()
                if vm.lookupCount > 0 {
                    Text("\(vm.lookupCount) word\(vm.lookupCount == 1 ? "" : "s")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.camuseanText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.camusean.opacity(0.12))
                        .clipShape(Capsule())
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
                        .animation(.spring(duration: 0.35, bounce: 0.2), value: vm.lookupCount)
                }
            }
            if learnedThisWeekCount > 0 {
                HStack(spacing: 4) {
                    Text("\(learnedThisWeekCount)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.camuseanText)
                    Text(learnedThisWeekCount == 1
                         ? "word learned this week"
                         : "words learned this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusDisplay: some View {
        Group {
            switch vm.phase {
            case .idle:
                Text("Starting…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)

            case .listening:
                if vm.partialTranscription.isEmpty {
                    if isFirstTime {
                        VStack(spacing: 10) {
                            Text("Say a word out loud")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("Speak any \(vm.sourceName) word you don't know — I'll define it aloud and save it for review.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .padding(.horizontal, 12)
                        }
                        .transition(.opacity)
                    } else {
                        Text("Say a word…")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text(vm.partialTranscription)
                        .font(.system(size: transcriptionSize, weight: .semibold, design: .serif))
                        .multilineTextAlignment(.center)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.88).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

            case .processing(let word):
                VStack(spacing: 14) {
                    Text(word)
                        .font(.system(size: resultWordSize, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 8)
                    DotsView()
                }

            case .result(let word, let definition, let formNote):
                VStack(spacing: 18) {
                    Text(word)
                        .font(.system(size: resultWordSize, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 8)
                    Rectangle()
                        .fill(Color.camusean.opacity(0.45))
                        .frame(width: 30, height: 1.5)
                    VStack(spacing: 8) {
                        Text(definition)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                        // Read, never heard — the spoken definition stays English-only on purpose.
                        if let formNote {
                            Text(formNote)
                                .font(.footnote)
                                .italic()
                                .foregroundStyle(Color.camuseanText)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))

            case .error(let msg):
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.08), value: vm.partialTranscription)
        .frame(minHeight: 140, alignment: .center)
    }

    private var isListening: Bool {
        if case .listening = vm.phase { return true }
        return false
    }

    private var isProcessing: Bool {
        if case .processing = vm.phase { return true }
        return false
    }

    // MARK: - Summary Sheet

    private var summarySheet: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.camusean.opacity(0.09))
                    .frame(width: 108, height: 108)
                Image(systemName: "book.closed")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Color.camusean)
            }
            Spacer().frame(height: 28)
            Text("Session complete")
                .font(.system(.title, design: .serif).weight(.bold))
            Spacer().frame(height: 12)
            Text(vm.lookupCount == 0
                 ? "No words looked up"
                 : "\(vm.lookupCount) word\(vm.lookupCount == 1 ? "" : "s") saved to review")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button { vm.showSummary = false } label: {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.camusean)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(30)
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Organic Mic View

private struct OrganicMicView: View {
    let isListening: Bool
    let isProcessing: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var breathe = false
    @State private var spinAngle: Double = 0

    var body: some View {
        Button(action: onTap) { dial }
            .buttonStyle(.plain)
            .accessibilityLabel(isListening ? "Listening" : isProcessing ? "Processing" : "Standby")
            .accessibilityHint(isListening || isProcessing ? "Cancels the current lookup" : "")
    }

    private var dial: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.camusean.opacity(0.13 - Double(i) * 0.03), lineWidth: 1)
                    .frame(
                        width: 88 + CGFloat(i) * 28,
                        height: 88 + CGFloat(i) * 28
                    )
                    .scaleEffect(!reduceMotion && breathe && isListening ? 1.13 : 1.0)
                    .opacity(isListening ? (reduceMotion ? 0.6 : (breathe ? 1.0 : 0.25)) : 0.0)
                    .animation(
                        reduceMotion ? nil :
                        (isListening
                            ? .easeInOut(duration: 1.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.24)
                            : .easeOut(duration: 0.4)),
                        value: breathe
                    )
            }

            if isProcessing {
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(
                        Color.camusean.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 102, height: 102)
                    .rotationEffect(.degrees(reduceMotion ? 0 : spinAngle))
            }

            // Grey base + amber overlay: crossfades on listening.
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 86, height: 86)
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.camusean, Color.camusean.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 86, height: 86)
                    .opacity(isListening ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: isListening)
            }
            .shadow(
                color: isListening ? Color.camusean.opacity(0.35) : .clear,
                radius: 20, y: 7
            )

            Image(systemName: "mic.fill")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.white)
                .opacity(isListening || isProcessing ? 1.0 : 0.45)
                .animation(.easeInOut(duration: 0.3), value: isListening)
        }
        // A wrapping Button, not .onTapGesture: only the Button gives VoiceOver the button
        // trait, activation, and Full Keyboard Access for this central control.
        .contentShape(Circle())
        .onAppear {
            guard !reduceMotion else { return }
            breathe = true
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spinAngle = 360
            }
        }
        .onChange(of: isListening) { _, newVal in
            if newVal && !reduceMotion { breathe = true }
        }
    }
}

// MARK: - Dots Loading View

private struct DotsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 5, height: 5)
                    .scaleEffect(!reduceMotion && animate ? 1.5 : (reduceMotion ? 1.0 : 0.6))
                    .opacity(!reduceMotion && animate ? 1.0 : (reduceMotion ? 0.6 : 0.3))
                    .animation(
                        reduceMotion ? nil :
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.17),
                        value: animate
                    )
            }
        }
        .onAppear { if !reduceMotion { animate = true } }
    }
}

#Preview {
    ReadingSessionView()
        .modelContainer(for: Word.self, inMemory: true)
}
