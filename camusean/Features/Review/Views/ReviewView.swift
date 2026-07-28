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

    // The big serif word. A fixed 48pt never moved with the reader's text-size setting;
    // @ScaledMetric keeps the design size at the default and scales it from there.
    @ScaledMetric(relativeTo: .largeTitle) private var cardWordSize: CGFloat = 48

    // The deck shown to the user: words with no schedule yet (new) or due now.
    private var words: [Word] {
        let now = Date()
        return allWords.filter { word in
            guard let nrd = word.nextReviewDate else { return true }
            return nrd <= now
        }
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
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray6))
                    .frame(width: 100, height: 100)
                Image(systemName: "books.vertical")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color(.systemGray2))
            }
            VStack(spacing: 8) {
                Text("No words yet")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                Text("Start a reading session\nto build your vocabulary.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(40)
    }

    private var allCaughtUp: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.camusean.opacity(0.10))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.camuseanText)
            }
            VStack(spacing: 8) {
                Text("All caught up")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                Text("Come back tomorrow.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
        .padding(40)
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
                                    swipeOut(direction: 1, action: markLearned)
                                } else if value.translation.width < -100 {
                                    swipeOut(direction: -1, action: markRepeat)
                                } else {
                                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                    .accessibilityAction(named: "Mark learned") { markLearned() }
                    .accessibilityAction(named: "Mark repeat") { markRepeat() }
            }

            Spacer()

            actionArea
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
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
                    Text(word.word)
                        .font(.system(size: cardWordSize, weight: .bold, design: .serif))
                        .minimumScaleFactor(0.4)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    Spacer().frame(height: 16)

                    if !isRevealed {
                        // Language tag
                        Text(word.sourceLanguage.components(separatedBy: "-").first ?? word.sourceLanguage)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())

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
                        // Definition
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
                HStack(spacing: 12) {
                    reviewButton(
                        label: "Repeat",
                        icon: "arrow.clockwise",
                        fg: Color.camuseanRepeat,
                        action: markRepeat
                    )
                    reviewButton(
                        label: "Learned",
                        icon: "checkmark",
                        fg: Color.camuseanSuccess,
                        action: markLearned
                    )
                }
            }
        }
    }

    private func reviewButton(label: String, icon: String, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(fg)
            .background(fg.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
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

    private func markLearned() {
        SRSScheduler.schedule(word: words[currentIndex], quality: 4)
        try? modelContext.save()
        // Filter recomputes; the scheduled-future row drops, next due card slides into currentIndex.
        resetCardState()
    }

    private func markRepeat() {
        SRSScheduler.schedule(word: words[currentIndex], quality: 2)
        try? modelContext.save()
        // SM-2 lapse pushes nextReviewDate to tomorrow; row drops from today's deck.
        resetCardState()
    }

    // Reached only through the confirmation dialog — see the card's "×" button.
    private func deleteCurrentWord() {
        guard currentIndex < words.count else { return }
        modelContext.delete(words[currentIndex])
        // Row removed entirely; the next due card slides into currentIndex.
        resetCardState()
    }

    private func resetCardState() {
        dragOffset = 0
        isRevealed = false
    }
}

#Preview {
    ReviewView()
        .modelContainer(for: Word.self, inMemory: true)
}
