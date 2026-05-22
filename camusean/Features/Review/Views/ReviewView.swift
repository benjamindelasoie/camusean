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
                    .font(.system(size: 22, weight: .semibold, design: .serif))
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
                    .foregroundStyle(Color.camusean)
            }
            VStack(spacing: 8) {
                Text("All caught up")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                Text("Come back tomorrow.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                LibraryView()
            } label: {
                Text("Browse all your words →")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.camusean)
            }
            .padding(.top, 8)
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
                // Decorative stack shadow cards
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .padding(.horizontal, 44)
                    .frame(height: cardHeight - 16)
                    .offset(y: 14)
                    .opacity(0.55)
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2)

                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .padding(.horizontal, 34)
                    .frame(height: cardHeight - 8)
                    .offset(y: 7)
                    .opacity(0.75)
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 3)

                // Live card
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

    private var cardHeight: CGFloat { 380 }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.camusean.opacity(0.65))
                        .frame(
                            width: geo.size.width * CGFloat(currentIndex) / CGFloat(max(words.count, 1)),
                            height: 3
                        )
                        .animation(.spring(duration: 0.4), value: currentIndex)
                }
            }
            .frame(height: 3)
            Text("\(currentIndex + 1) of \(words.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }

    private func flashcard(for word: Word) -> some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.11), radius: 22, y: 8)
            .frame(height: cardHeight)
            .overlay(alignment: .topTrailing) {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .padding(.top, 6)
                .padding(.trailing, 10)
                .accessibilityLabel("Delete word")
            }
            .padding(.horizontal, 24)
            .overlay {
                VStack(spacing: 0) {
                    Spacer()

                    Text(word.word)
                        .font(.system(size: 48, weight: .bold, design: .serif))
                        .minimumScaleFactor(0.4)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    Spacer().frame(height: 16)

                    if !isRevealed {
                        // Language tag
                        Text(word.sourceLanguage.components(separatedBy: "-").first ?? word.sourceLanguage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())

                        Spacer()

                        // Swipe direction hints — visible only while dragging
                        HStack {
                            Label("Repeat", systemImage: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(.systemOrange))
                                .opacity(dragOffset < -20 ? 1 : 0)
                                .animation(.easeOut(duration: 0.12), value: dragOffset)

                            Spacer()

                            Label("Learned", systemImage: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.40))
                                .opacity(dragOffset > 20 ? 1 : 0)
                                .animation(.easeOut(duration: 0.12), value: dragOffset)
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 26)
                    } else {
                        // Definition
                        Rectangle()
                            .fill(Color.camusean.opacity(0.3))
                            .frame(height: 1.5)
                            .padding(.horizontal, 28)

                        Spacer().frame(height: 18)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 14) {
                                if word.definition.isEmpty {
                                    Text("Definition unavailable")
                                        .foregroundStyle(.secondary)
                                        .italic()
                                } else {
                                    Text(word.definition)
                                        .font(.callout)
                                        .foregroundStyle(.primary.opacity(0.85))
                                        .multilineTextAlignment(.center)
                                        .lineSpacing(4)
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

                        Spacer().frame(height: 24)
                    }
                }
            }
            .animation(.spring(duration: 0.42, bounce: 0.08), value: isRevealed)
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Color.camusean)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                }
            } else {
                HStack(spacing: 14) {
                    reviewButton(
                        label: "Repeat",
                        icon: "arrow.clockwise",
                        fg: Color(.systemOrange),
                        action: markRepeat
                    )
                    reviewButton(
                        label: "Learned",
                        icon: "checkmark",
                        fg: Color(red: 0.18, green: 0.62, blue: 0.40),
                        action: markLearned
                    )
                }
            }
        }
    }

    private func reviewButton(label: String, icon: String, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(fg)
            .background(fg.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14))
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

    private func dismiss() {
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
