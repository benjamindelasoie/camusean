import Dependencies
import SwiftUI
import SwiftData

struct ReviewView: View {
    @Dependency(\.speechSynthesizer) private var synth

    // Filtered to "due now" in a computed property so the Date() cutoff refreshes each render.
    @Query(sort: \Word.timestamp) private var allWords: [Word]

    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex = 0
    @State private var isRevealed = false
    @State private var dragOffset: CGFloat = 0
    @State private var showDeleteConfirm = false
    @State private var lastGrade: GradeSnapshot?


    @AppStorage("autoSpeakOnReveal") private var autoSpeakOnReveal = false

    /// Fixed denominator, captured once when the deck first appears. The live `words.count`
    /// shrinks as cards are graded, which would read as "1 of 42 → 1 of 41" — work growing.
    @State private var sessionTotal: Int?

    /// `total - remaining`, so undo is free: restoring a word to the filter moves both counts
    /// back with no separate bookkeeping. Clamped because a card can re-enter the deck.
    private var reviewedCount: Int {
        guard let sessionTotal else { return 0 }
        return min(max(0, sessionTotal - words.count), sessionTotal)
    }

    private var cardPosition: Int {
        guard let sessionTotal, sessionTotal > 0 else { return 0 }
        return min(reviewedCount + 1, sessionTotal)
    }

    // @ScaledMetric so the word tracks the reader's text-size setting; a fixed 48pt did not.
    @ScaledMetric(relativeTo: .largeTitle) private var cardWordSize: CGFloat = 48

    /// What a grade overwrote, so undo can restore it. Holds identity, not the word: the deck
    /// is recomputed on restore and the card must be found by identity, not by position.
    private struct GradeSnapshot {
        let id: PersistentIdentifier
        let interval: Int
        let easeFactor: Double
        let nextReviewDate: Date?
        let gradeLabel: String
    }

    private var words: [Word] {
        WordScheduleRules.dueDeck(from: allWords)
    }

    /// The card being reviewed, or nil when the deck is empty. Every mutation goes through
    /// this bounds-checked accessor so the deck and index disagreeing can't crash.
    private var currentWord: Word? {
        words.indices.contains(currentIndex) ? words[currentIndex] : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if allWords.isEmpty {
                    emptyState
                } else if words.isEmpty || currentIndex >= words.count {
                    allCaughtUp
                } else {
                    cardStack
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { beginSessionIfNeeded() }
            .onChange(of: words.count) { _, _ in beginSessionIfNeeded() }
            // Speech must not outlive the screen that started it.
            .onDisappear { stopCardSpeech() }
            .confirmationDialog(
                "Delete this word?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteCurrentWord() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will be removed from your library and your review schedule. This can't be undone.")
            }
            .toolbar {
                if !allWords.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            LibraryView()
                        } label: {
                            Image(systemName: "books.vertical")
                                .accessibilityLabel("Library")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "books.vertical",
            title: "No words yet",
            message: "Start a reading session\nto build your vocabulary."
        )
    }

    private var allCaughtUp: some View {
        EmptyStateView(
            systemImage: "checkmark",
            title: "All caught up",
            message: "Come back tomorrow.",
            tint: .camuseanText,
            circleFill: Color.camusean.opacity(0.10)
        ) {
            NavigationLink {
                LibraryView()
            } label: {
                Text("Browse all your words →")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.camuseanText)
                    // 44pt minimum hit target — the label alone is ~20pt tall.
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 28)

            Spacer()

            deck

            Spacer()

            VStack(spacing: 4) {
                actionArea
                undoBar
            }
            .animation(.easeInOut(duration: 0.2), value: lastGrade == nil)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    // A floor, not a fixed height: the card grows with its content and scales with text size.
    @ScaledMetric(relativeTo: .largeTitle) private var cardMinHeight: CGFloat = 260

    // MARK: - The deck

    // Only the top card carries content; the rest are blank edges for depth.
    private static let visibleDepth = 3
    // Drag distance at which a swipe commits; also what the rise animation is measured against.
    private static let commitDistance: CGFloat = 100

    // Measured so the cards behind match the top card's height, which changes on reveal.
    @State private var topCardHeight: CGFloat = 0

    /// Each card is a sibling with its own identity (`persistentModelID`), not one reused view:
    /// the top card leaves and the one beneath becomes the top, so nothing slides in.
    private var deck: some View {
        let upcoming = Array(words.dropFirst(currentIndex).prefix(Self.visibleDepth))
        // 0 at rest, 1 once the drag commits; drives the card beneath rising continuously.
        let riseProgress = min(1, abs(dragOffset) / Self.commitDistance)

        return ZStack {
            // Reversed so the top card is added last and therefore drawn in front.
            ForEach(Array(upcoming.enumerated()).reversed(), id: \.element.persistentModelID) { depth, word in
                Group {
                    if depth == 0 {
                        topCard(word)
                    } else {
                        restingCard(depth: depth, riseProgress: riseProgress)
                    }
                }
            }
        }
    }

    private func topCard(_ word: Word) -> some View {
        flashcard(for: word)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topCardHeight = $0 }
            // Badge sits on the edge the card is travelling away from, so it never covers the word.
            .overlay(alignment: dragOffset > 0 ? .topLeading : .topTrailing) {
                swipeVerdictBadge.padding(22)
            }
            .offset(x: dragOffset)
            .rotationEffect(.degrees(Double(dragOffset) / 24))
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation.width }
                    .onEnded { value in
                        if value.translation.width > Self.commitDistance {
                            swipeOut(direction: 1) { grade(.good) }
                        } else if value.translation.width < -Self.commitDistance {
                            swipeOut(direction: -1) { grade(.again) }
                        } else {
                            withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            // VoiceOver cannot swipe-to-grade, so every grade is also a named action.
            .accessibilityAction(named: "Again") { grade(.again) }
            .accessibilityAction(named: "Good") { grade(.good) }
            .accessibilityAction(named: "Easy") { grade(.easy) }
            .accessibilityAction(named: "Hear word") { speakCurrentWord() }
    }

    /// A card below the top one, deliberately blank — showing the next word would spoil it.
    private func restingCard(depth: Int, riseProgress: CGFloat) -> some View {
        // Narrower and lower per level, interpolating toward the top slot as the top is dragged away.
        let effectiveDepth = CGFloat(depth) - riseProgress
        let scale = 1 - 0.05 * effectiveDepth
        let yOffset = 22 * effectiveDepth

        return RoundedRectangle(cornerRadius: 24)
            .fill(Color.camuseanCard)
            .overlay {
                // A hairline stroke: a white card on white is otherwise defined only by a shadow
                // that's nearly invisible behind another card, so the edges read as a smudge.
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.primary.opacity(0.10 - 0.02 * effectiveDepth), lineWidth: 1)
            }
            .frame(height: topCardHeight > 0 ? topCardHeight : cardMinHeight)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            .padding(.horizontal, 24)
            .scaleEffect(scale)
            .offset(y: yOffset)
            .accessibilityHidden(true)
    }

    /// Fills with cards completed (measured against the session's starting deck), so it starts
    /// empty and reaches full on the last grade.
    private var progressBar: some View {
        let total = sessionTotal ?? words.count
        let done = reviewedCount
        let fraction = total > 0 ? Double(done) / Double(total) : 0

        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.camusean)
                        .frame(width: max(0, geo.size.width * fraction), height: 6)
                        .animation(.spring(duration: 0.4), value: done)
                }
            }
            .frame(height: 6)

            HStack {
                Text("Card \(cardPosition) of \(total)")
                Spacer()
                Text(remainingLabel(done: done, total: total))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Review progress")
        .accessibilityValue("Card \(cardPosition) of \(total). \(total - done) remaining.")
    }

    private func remainingLabel(done: Int, total: Int) -> String {
        let left = max(0, total - done)
        if done == 0 { return "\(left) to review" }
        return "\(left) left"
    }

    private func flashcard(for word: Word) -> some View {
        cardBody(for: word)
            .frame(maxWidth: .infinity)
            .frame(minHeight: cardMinHeight)
            .background {
                ZStack {
                    // The two cards peeking out behind, drawn in the background so they inherit
                    // the live card's height rather than a shared constant.
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.camuseanCard)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .offset(y: 16)
                        .opacity(0.55)
                        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)

                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.camuseanCard)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .offset(y: 8)
                        .opacity(0.75)
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)

                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.camuseanCard)
                        .shadow(color: .black.opacity(0.11), radius: 22, y: 8)
                }
            }
            .overlay(alignment: .topTrailing) {
                // 44pt hit area on a card the reader is actively dragging, so a mis-swipe can't
                // trigger it; the delete is destructive and irreversible, so it asks first.
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Delete word")
            }
            .padding(.horizontal, 24)
            .animation(.spring(duration: 0.42, bounce: 0.08), value: isRevealed)
    }

    private func cardBody(for word: Word) -> some View {
                VStack(spacing: 0) {
                    // The word must not be a Button: a Button wins the gesture against the ancestor
                    // DragGesture, so dragging from the card's middle (where a thumb lands) did
                    // nothing. Keeping the speaker a separate control gives the drag the whole card.
                    HStack(spacing: 10) {
                        Text(word.word)
                            .font(.system(size: cardWordSize, weight: .bold, design: .serif))
                            .minimumScaleFactor(0.4)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        Button { speak(word) } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: max(14, cardWordSize * 0.32)))
                                .foregroundStyle(Color.camuseanText)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hear \(word.word)")
                    }
                    .padding(.horizontal, 20)

                    Spacer().frame(height: 12)

                    cardStatusRow(for: word)

                    if !isRevealed {
                        Spacer().frame(height: 24)
                    } else {
                        // Clearance so the rule below doesn't draw through the status pill.
                        Spacer().frame(height: 16)

                        Rectangle()
                            .fill(Color.camusean.opacity(0.3))
                            .frame(height: 1.5)
                            .padding(.horizontal, 28)

                        Spacer().frame(height: 18)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 12) {
                                if word.definition.isEmpty {
                                    Text("Definition unavailable")
                                        .foregroundStyle(.secondary)
                                        .italic()
                                } else {
                                    Text(word.definition)
                                        .font(.title3)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.center)
                                        .lineSpacing(4)
                                    // e.g. "Past participle of disparaître". nil before v1.5 and
                                    // for words already in their own dictionary form.
                                    if let formNote = word.formNote {
                                        Text(formNote)
                                            .font(.footnote)
                                            .italic()
                                            .foregroundStyle(Color.camuseanText)
                                            .multilineTextAlignment(.center)
                                    }
                                    if !word.exampleSentence.isEmpty {
                                        Text(word.exampleSentence)
                                            .font(.callout)
                                            .italic()
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                            .lineSpacing(4)
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                        }
                    }
                }
                // Take the card's ideal height; without this the layout stretches to fill the screen.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 28)
    }

    // MARK: - Action Area

    private var actionArea: some View {
        Group {
            if !isRevealed {
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.1)) {
                        isRevealed = true
                    }
                    if autoSpeakOnReveal { speakCurrentWord() }
                } label: {
                    Text("Reveal definition")
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.camusean)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            } else {
                // Easy (q=5) is the only grade that raises the ease factor; without it the
                // deck could only ever get stricter.
                HStack(spacing: 8) {
                    ForEach(ReviewGrade.allCases) { g in
                        reviewButton(grade: g)
                    }
                }
            }
        }
    }

    private func reviewButton(grade g: ReviewGrade) -> some View {
        // Distinct tints because Again and Good mean opposite things to the scheduler and must
        // not read as the same button at a glance.
        let tint: Color = switch g {
        case .again: .camuseanRepeat
        case .good:  .primary
        case .easy:  .camuseanSuccess
        }
        return Button { grade(g) } label: {
            VStack(spacing: 8) {
                Image(systemName: g.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                Text(g.label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityLabel(g.label)
        .accessibilityHint(g.isLapse ? "Shows this word again tomorrow" : "Schedules this word further out")
    }

    /// Shown briefly after a grade so a mis-swipe is recoverable.
    @ViewBuilder
    private var undoBar: some View {
        if let snapshot = lastGrade {
            Button { undoLastGrade() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Undo \(snapshot.gradeLabel.lowercased())")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.camuseanText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .transition(.opacity)
        }
    }

    // MARK: - Swipe Logic

    private func swipeOut(direction: CGFloat, action: @escaping @MainActor () -> Void) {
        withAnimation(.easeIn(duration: 0.2)) {
            dragOffset = direction * 500
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            action()
        }
    }

    // MARK: - Grading

    private func grade(_ grade: ReviewGrade) {
        guard let word = currentWord else { return }
        // Snapshot before mutating so undo can restore the prior schedule.
        lastGrade = GradeSnapshot(
            id: word.persistentModelID,
            interval: word.interval,
            easeFactor: word.easeFactor,
            nextReviewDate: word.nextReviewDate,
            gradeLabel: grade.label
        )
        stopCardSpeech()
        SRSScheduler.schedule(word: word, quality: grade.quality)
        try? modelContext.save()
        // The graded word drops out of the filter and the next due card slides into the same
        // index; currentIndex must not advance — see `undoLastGrade`.
        resetCardState()
    }

    /// Puts the last graded word back and returns to it. The word re-enters the timestamp-sorted
    /// deck at its chronological position, which can be before currentIndex, so undo seeks the
    /// card by identity rather than trusting the index.
    private func undoLastGrade() {
        guard let snapshot = lastGrade,
              let word = allWords.first(where: { $0.persistentModelID == snapshot.id })
        else { return }

        stopCardSpeech()
        word.interval = snapshot.interval
        word.easeFactor = snapshot.easeFactor
        word.nextReviewDate = snapshot.nextReviewDate
        try? modelContext.save()

        // The mutation above recomputed the deck; find the restored card by identity.
        if let restored = words.firstIndex(where: { $0.persistentModelID == snapshot.id }) {
            currentIndex = restored
        }
        lastGrade = nil   // one level of undo; a second press must no-op, not corrupt state
        resetCardState()
    }

    private func deleteCurrentWord() {
        guard let word = currentWord else { return }
        stopCardSpeech()
        modelContext.delete(word)
        lastGrade = nil   // the snapshot's word no longer exists
        resetCardState()
    }

    private func resetCardState() {
        dragOffset = 0
        isRevealed = false
    }

    /// Guarded on `sessionTotal == nil` so grading never re-baselines the denominator while the
    /// deck drains; cleared once the deck empties so returning later starts a fresh count.
    private func beginSessionIfNeeded() {
        let due = words.count
        if due == 0 {
            sessionTotal = nil
        } else if sessionTotal == nil {
            sessionTotal = due
        }
    }

    // MARK: - Swipe verdict

    /// What the swipe is about to do, shown mid-drag before it commits. Icons (check vs.
    /// counter-clockwise arrow) carry the meaning alongside the red/green tints, so it reads
    /// without colour vision.
    @ViewBuilder
    private var swipeVerdictBadge: some View {
        // Ignore the first few points so a tap or a scroll does not flash a verdict.
        let travel = max(0, abs(dragOffset) - 12)
        let strength = min(1, travel / (Self.commitDistance - 12))
        let isCommitting = abs(dragOffset) >= Self.commitDistance
        let goingRight = dragOffset > 0

        if strength > 0 {
            let grade: ReviewGrade = goingRight ? .good : .again
            let tint: Color = goingRight ? .camuseanSuccess : .camuseanAgain

            HStack(spacing: 8) {
                Image(systemName: goingRight ? "checkmark" : "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .heavy))
                Text(grade.label.uppercased())
                    .font(.subheadline.weight(.heavy))
                    .kerning(1.5)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(tint, in: .capsule)
            .scaleEffect(0.7 + 0.3 * strength)
            .opacity(Double(strength))
            .rotationEffect(.degrees(goingRight ? -8 : 8))
            .shadow(color: tint.opacity(0.35), radius: isCommitting ? 18 : 8, y: 4)
            .animation(.easeOut(duration: 0.12), value: isCommitting)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Card status

    @ViewBuilder
    private func cardStatusRow(for word: Word) -> some View {
        let progress = WordScheduleRules.progress(for: word)
        let provenance = word.book.map { "From \($0.title). " } ?? ""
        HStack(spacing: 8) {
            if let title = word.book?.title {
                Label(title, systemImage: "book.closed")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            statusPill(progress)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(provenance + statusText(progress))
    }

    private func statusPill(_ progress: WordProgress) -> some View {
        let tint: Color = switch progress {
        case .new: .camuseanText
        case .struggling: .camuseanRepeat
        case .learning: .secondary
        case .mature: .camuseanSuccess
        }
        return Text(statusText(progress))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func statusText(_ progress: WordProgress) -> String {
        switch progress {
        case .new: return "New"
        case .struggling: return "Struggling"
        case .learning(let days): return days == 1 ? "1 day" : "\(days) days"
        case .mature(let days): return "\(days) days"
        }
    }

    // MARK: - Audio

    /// The locale must be resolved, not read: `Word.sourceLanguage` stores a display name
    /// ("French"), not a BCP-47 tag, so passing it straight to TTS matches no voice and the
    /// synthesizer falls back to an English voice reading a French word.
    private func speak(_ word: Word) {
        let locale = ReadingLanguage.locale(forName: word.sourceLanguage)
        let speaker = synth
        Task { @MainActor in
            // performPlayback suspends any live capture and hands the mic back after, so this
            // is safe from either tab.
            await AudioSessionManager.shared.performPlayback {
                await speaker.speak(word.word, locale)
            }
        }
    }

    private func speakCurrentWord() {
        guard let word = currentWord else { return }
        speak(word)
    }

    /// Speech must not outlive the card that started it, or the previous word talks over the
    /// next; grading, undo, delete, and leaving the screen all call this.
    private func stopCardSpeech() {
        synth.stop()
    }
}

#Preview {
    ReviewView()
        .modelContainer(for: Word.self, inMemory: true)
}
