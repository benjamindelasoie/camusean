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

            ZStack {
                // Live card. The decorative cards peeking out behind it are drawn in its
                // .background, so they track its height instead of a shared constant.
                flashcard(for: words[currentIndex])
                    .offset(x: dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset) / 24))
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = $0.translation.width }
                            .onEnded { value in
                                if value.translation.width > 100 {
                                    swipeOut(direction: 1) { grade(.good) }
                                } else if value.translation.width < -100 {
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

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.camusean)
                        // The label reads "1 of 29", so the bar has to agree: card 1 of 29
                        // is 1/29 done, not 0/29. It used to divide by `currentIndex`, which
                        // rendered an empty track under a label saying "1 of 29".
                        .frame(
                            width: geo.size.width * CGFloat(currentIndex + 1) / CGFloat(max(words.count, 1)),
                            height: 6
                        )
                        .animation(.spring(duration: 0.4), value: currentIndex)
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("Card \(currentIndex + 1) of \(words.count)")
            Text("\(currentIndex + 1) of \(words.count)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
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
                    // Tap the word to hear it. A plain .onTapGesture here would fight the
                    // card's parent DragGesture, so this is a Button — SwiftUI gives a button
                    // priority over an ancestor drag, and VoiceOver gets a real control
                    // instead of decorated text.
                    Button { speak(word) } label: {
                        HStack(spacing: 10) {
                            Text(word.word)
                                .font(.system(size: cardWordSize, weight: .bold, design: .serif))
                                .minimumScaleFactor(0.4)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: max(14, cardWordSize * 0.32)))
                                .foregroundStyle(Color.camuseanText)
                        }
                        .padding(.horizontal, 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(word.word)
                    .accessibilityHint("Hear it pronounced")

                    Spacer().frame(height: 12)

                    cardStatusRow(for: word)

                    if !isRevealed {
                        Spacer().frame(height: 32)

                        // Swipe direction hints — visible only while dragging
                        HStack {
                            Label("Repeat", systemImage: "arrow.clockwise")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.camuseanRepeat)
                                .opacity(dragOffset < -20 ? 1 : 0)
                                .animation(.easeOut(duration: 0.12), value: dragOffset)

                            Spacer()

                            Label("Learned", systemImage: "checkmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.camuseanSuccess)
                                .opacity(dragOffset > 20 ? 1 : 0)
                                .animation(.easeOut(duration: 0.12), value: dragOffset)
                        }
                        .padding(.horizontal, 28)
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
