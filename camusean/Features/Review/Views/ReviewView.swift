import SwiftUI
import SwiftData

struct ReviewView: View {
    // Unfiltered + sorted; we filter to "due now" in a computed property so the
    // cutoff (Date()) refreshes on each render rather than being captured once.
    @Query(sort: \Word.timestamp) private var allWords: [Word]

    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex = 0
    @State private var isRevealed = false
    @State private var dragOffset: CGFloat = 0
    @State private var showDeleteConfirm = false
    @State private var lastGrade: GradeSnapshot?


    @AppStorage("autoSpeakOnReveal") private var autoSpeakOnReveal = false

    /// How many cards were due when this review session started.
    ///
    /// The deck is a live filter over "what is due right now", so grading a card removes it
    /// and `words.count` shrinks. Using that as the denominator produced "1 of 42" → "1 of
    /// 41" → "1 of 40": the position never moved and the total counted down, which reads as
    /// the work growing rather than shrinking. A session needs a fixed total to measure
    /// against, captured once when the deck first appears.
    @State private var sessionTotal: Int?

    /// Cards handled so far, derived rather than counted.
    ///
    /// `total - remaining` means undo is free: restoring a word puts it back in the filter,
    /// remaining goes up, and reviewed goes down without any separate bookkeeping to keep in
    /// sync. Clamped because a card can in principle re-enter the deck mid-session.
    private var reviewedCount: Int {
        guard let sessionTotal else { return 0 }
        return min(max(0, sessionTotal - words.count), sessionTotal)
    }

    /// 1-based position of the card on screen, for "N of M".
    private var cardPosition: Int {
        guard let sessionTotal, sessionTotal > 0 else { return 0 }
        return min(reviewedCount + 1, sessionTotal)
    }

    // The big serif word. A fixed 48pt never moved with the reader's text-size setting;
    // @ScaledMetric keeps the design size at the default and scales it from there.
    @ScaledMetric(relativeTo: .largeTitle) private var cardWordSize: CGFloat = 48

    /// What a grade overwrote, so undo can put it back exactly.
    ///
    /// Holds the word's identity rather than the word: after restoring, the deck is
    /// recomputed and the card has to be found again by identity, not by position.
    private struct GradeSnapshot {
        let id: PersistentIdentifier
        let interval: Int
        let easeFactor: Double
        let nextReviewDate: Date?
        let gradeLabel: String
    }

    // The deck shown to the user: words with no schedule yet (new) or due now.
    private var words: [Word] {
        WordScheduleRules.dueDeck(from: allWords)
    }

    /// The card being reviewed, or nil when the deck is empty.
    ///
    /// Every mutation goes through this. Previously three call sites indexed `words` by hand
    /// and only one of them checked the bounds first — an out-of-range crash waiting for the
    /// deck and the index to disagree, which undo and a third grade button both make easier.
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
            // Capture the session's denominator once, the first time there is a deck to
            // measure. Re-derived on a later appearance only if the session was finished.
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

    /// Floor, not a fixed height. The card used to be pinned at 380pt regardless of what
    /// was on it, so at default text size the revealed side was roughly 60% empty white —
    /// it only looked right at accessibility sizes, which is what it had been sized for.
    /// It now grows with its content and scales with the reader's text-size setting.
    @ScaledMetric(relativeTo: .largeTitle) private var cardMinHeight: CGFloat = 260

    // MARK: - The deck

    /// How many cards are drawn. Only the top one carries content; the rest are edges.
    private static let visibleDepth = 3
    /// Drag distance at which a swipe commits, and the distance the rise animation is
    /// measured against.
    private static let commitDistance: CGFloat = 100

    /// Measured height of the top card, so the cards behind match it exactly. The top card's
    /// height changes when the definition is revealed, and a fixed height for the ones
    /// behind would leave them poking out at the wrong depth.
    @State private var topCardHeight: CGFloat = 0

    /// The real stack.
    ///
    /// Previously this was ONE card view with two empty rounded rectangles drawn inside its
    /// `.background`. Two consequences, both of which read as wrong:
    ///
    ///   - the "stack" translated and rotated *with* the top card, because it was part of it
    ///   - grading reused the same view with new content, so SwiftUI animated it back from
    ///     wherever the last card flew off to, and the next word slid in from the side
    ///
    /// Now each card is a sibling with its own identity (`persistentModelID`). The top card
    /// leaves; the one beneath was already on screen and simply becomes the top. Nothing
    /// slides in, because nothing new arrives.
    ///
    ///        ┌─────────────┐        drag ──▶   ┌─────────────┐
    ///      ┌─┤   card 1    ├─┐               ┌─┤   card 2    ├─┐   card 2 rises toward
    ///    ┌─┤ └─────────────┘ ├─┐           ┌─┤ └─────────────┘ ├─┐  the top slot as
    ///    │ │    card 2       │ │           │ │    card 3       │ │  card 1 is dragged
    ///    └─┴─────────────────┴─┘           └─┴─────────────────┴─┘
    private var deck: some View {
        let upcoming = Array(words.dropFirst(currentIndex).prefix(Self.visibleDepth))
        // 0 at rest, 1 once the drag has travelled far enough to commit. Drives the card
        // beneath rising into place, so the stack responds continuously to the gesture
        // rather than jumping when the finger lifts.
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
            // Badge sits on the edge the card is travelling AWAY from, so it never covers
            // the word — the thing you are actually being asked to judge.
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

    /// A card below the top one. Deliberately blank — showing the next word would spoil the
    /// card before it is turned over. What it contributes is the edge, the depth, and the
    /// promise that there is more underneath.
    private func restingCard(depth: Int, riseProgress: CGFloat) -> some View {
        // Each level sits slightly narrower and lower. As the top card is dragged away, the
        // level below interpolates toward the top slot.
        let effectiveDepth = CGFloat(depth) - riseProgress
        let scale = 1 - 0.05 * effectiveDepth
        let yOffset = 22 * effectiveDepth

        return RoundedRectangle(cornerRadius: 24)
            .fill(Color.camuseanCard)
            .overlay {
                // A white card on a white page is defined only by its shadow, and a shadow
                // cast by something already behind another card is nearly invisible — which
                // is why the stack previously read as a smudge rather than as paper. The
                // hairline gives each edge an actual line, in both appearances.
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

    /// Session progress, measured against the deck as it was when the session began.
    ///
    /// The bar fills with cards *completed*, so it starts empty and reaches full on the last
    /// grade. The label names the card you are on. Together they answer the two questions a
    /// reader actually has mid-session: how far in am I, and how much is left.
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
                    // The two cards peeking out behind. Drawn in the background so they
                    // inherit the live card's height rather than a shared constant.
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
                // Destructive and irreversible, so it asks first. 44pt hit area — it used to
                // be 32pt in the corner of a card the reader is actively dragging, which made
                // a mis-swipe capable of silently deleting the word.
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
                    // The word is content; the speaker glyph is the control.
                    //
                    // The word used to be wrapped in a Button for tap-to-hear, and a Button
                    // wins the gesture against an ancestor DragGesture — so dragging from the
                    // middle of the card, which is exactly where a thumb lands, did nothing
                    // at all. Only the empty surface below it could be swiped. Splitting them
                    // gives the drag the whole card back and still leaves VoiceOver a real,
                    // labelled control (plus the card's "Hear word" action).
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
                        // The old corner labels ("Repeat" / "Learned", 11pt, unrevealed side
                        // only) are gone. The verdict now shows as a full badge over the
                        // card — see `swipeVerdictBadge` — which works on both sides and is
                        // legible mid-gesture.
                        Spacer().frame(height: 24)
                    } else {
                        // Definition. The status pill needs clearance or the rule draws
                        // straight through it.
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
                                    // The definition is the payoff — the reason the card was
                                    // flipped. It used to render at .callout, smaller than the
                                    // example sentence read, which inverted the hierarchy.
                                    Text(word.definition)
                                        .font(.title3)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.center)
                                        .lineSpacing(4)
                                    // Where this form comes from, e.g. "Past participle of
                                    // disparaître". nil for words saved before v1.5 and for words
                                    // that are already their own dictionary form.
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
                // Take the card's ideal height, not whatever the surrounding Spacers offer.
                // Without this the inner layout stretched to fill the screen, which is how
                // the card ended up ~60% empty white at default text size.
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
                // Three grades, not two. Easy (q=5) is the only one that raises an ease
                // factor — without it the deck could only ever get stricter.
                HStack(spacing: 8) {
                    ForEach(ReviewGrade.allCases) { g in
                        reviewButton(grade: g)
                    }
                }
            }
        }
    }

    private func reviewButton(grade g: ReviewGrade) -> some View {
        // Three visually distinct tints. Again and Good were both in the amber family and
        // read as the same button at a glance — which is the one mistake a grading row
        // cannot afford, since the two mean opposite things to the scheduler.
        let tint: Color = switch g {
        case .again: .camuseanRepeat        // burnt orange — the lapse
        case .good:  .primary               // neutral — the ordinary answer
        case .easy:  .camuseanSuccess       // green — the only one that raises ease
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
        // Snapshot before mutating so undo can restore the exact prior schedule.
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
        // The deck is a filter, not a stored list: the freshly scheduled word drops out and
        // the next due card slides into the same index. currentIndex deliberately does not
        // advance — see `undoLastGrade` for why that matters.
        resetCardState()
    }

    /// Puts the last graded word back and returns to it.
    ///
    /// Restoring alone is not enough. `allWords` is sorted by `timestamp`, so the word
    /// re-enters the deck at its chronological position, which can be *before* the current
    /// index — every later card shifts by one and `currentIndex` silently points at a
    /// different word. Seeking by identity is what makes undo land on the card you undid.
    private func undoLastGrade() {
        guard let snapshot = lastGrade,
              let word = allWords.first(where: { $0.persistentModelID == snapshot.id })
        else { return }

        stopCardSpeech()
        word.interval = snapshot.interval
        word.easeFactor = snapshot.easeFactor
        word.nextReviewDate = snapshot.nextReviewDate
        try? modelContext.save()

        // Deck has been recomputed by the mutation above; find the restored card by identity.
        if let restored = words.firstIndex(where: { $0.persistentModelID == snapshot.id }) {
            currentIndex = restored
        }
        lastGrade = nil   // one level of undo; a second press must no-op, not corrupt state
        resetCardState()
    }

    // Reached only through the confirmation dialog — see the card's "×" button.
    private func deleteCurrentWord() {
        guard let word = currentWord else { return }
        stopCardSpeech()
        modelContext.delete(word)
        lastGrade = nil   // the snapshot's word no longer exists
        // Row removed entirely; the next due card slides into currentIndex.
        resetCardState()
    }

    private func resetCardState() {
        dragOffset = 0
        isRevealed = false
    }

    /// Starts a session when there is a deck and none is running.
    ///
    /// Guarded on `sessionTotal == nil` so grading never re-baselines the denominator — the
    /// whole point is that it stays put while the deck drains. Cleared once the deck empties
    /// so returning later starts a fresh count rather than resuming a finished one.
    private func beginSessionIfNeeded() {
        let due = words.count
        if due == 0 {
            sessionTotal = nil
        } else if sessionTotal == nil {
            sessionTotal = due
        }
    }

    // MARK: - Swipe verdict

    /// What the swipe is about to do, shown while the finger is still down.
    ///
    /// Replaces two small text labels ("Repeat" / "Learned") that appeared only on the
    /// unrevealed side and only announced themselves at 11pt in the card's bottom corners.
    /// A gesture with no button attached has to say what it means *before* it commits, at a
    /// size and colour you cannot miss mid-drag.
    ///
    /// Red and green carry the meaning here, so the icons carry it too — a check and a
    /// counter-clockwise arrow are distinguishable without colour vision, and the two tints
    /// differ in lightness as well as hue.
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
            // Firms up as you approach the commit distance, so the gesture has a felt
            // threshold rather than an invisible one.
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

    /// Where the word came from and how well it is known — both derived from data the app
    /// already stores, so neither costs a schema change.
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

    /// Speaks the current word in the language it was read in.
    ///
    /// The locale has to be resolved, not read. `Word.sourceLanguage` stores a display NAME
    /// ("French"), not a BCP-47 tag — `SessionViewModel.sourceName` reads it out of
    /// UserDefaults and `saveWord` persists it verbatim. Passing it straight to
    /// `TTSService.speak(language:)` matches nothing (`bestVoice` compares the first two
    /// characters, and "Fr" never matches "fr-FR"), the fallback voice constructor returns
    /// nil, and the synthesizer falls back to the device default — a French word read aloud
    /// by an English voice. See the TODOS entry for the underlying field fix.
    private func speak(_ word: Word) {
        let locale = ReadingLanguage.locale(forName: word.sourceLanguage)
        Task { @MainActor in
            // performPlayback suspends capture if a reading session is live and hands the
            // microphone back afterwards, so this is safe from either tab.
            await AudioSessionManager.shared.performPlayback {
                await TTSService.shared.speak(word.word, language: locale)
            }
        }
    }

    private func speakCurrentWord() {
        guard let word = currentWord else { return }
        speak(word)
    }

    /// Speech must not outlive the card that started it — grading, undo, delete, and leaving
    /// the screen all cut it off, otherwise the previous word talks over the next one.
    private func stopCardSpeech() {
        TTSService.shared.stopSpeaking()
    }
}

#Preview {
    ReviewView()
        .modelContainer(for: Word.self, inMemory: true)
}
