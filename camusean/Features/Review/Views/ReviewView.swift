import SwiftUI
import SwiftData

struct ReviewView: View {
    @Query(filter: #Predicate<Word> { !$0.isKnown }, sort: \Word.timestamp)
    private var words: [Word]

    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex = 0
    @State private var isRevealed = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    emptyState
                } else if currentIndex >= words.count {
                    allCaughtUp
                } else {
                    cardStack
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No words yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Start a reading session to collect words.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var allCaughtUp: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("All caught up!")
                .font(.title2)
                .fontWeight(.semibold)
            Text("You've reviewed all your words.")
                .foregroundStyle(.secondary)
            Button("Start over") {
                currentIndex = 0
                isRevealed = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var cardStack: some View {
        VStack {
            Text("\(currentIndex + 1) of \(words.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top)

            Spacer()

            flashcard(for: words[currentIndex])
                .offset(x: dragOffset)
                .rotationEffect(.degrees(Double(dragOffset) / 20))
                .gesture(
                    DragGesture()
                        .onChanged { dragOffset = $0.translation.width }
                        .onEnded { value in
                            if value.translation.width < -100 {
                                markKnown()
                            } else if value.translation.width > 100 {
                                keepWord()
                            } else {
                                withAnimation { dragOffset = 0 }
                            }
                        }
                )

            Spacer()

            if !isRevealed {
                Button("Reveal") {
                    withAnimation { isRevealed = true }
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 32)
            } else {
                HStack(spacing: 40) {
                    Button {
                        markKnown()
                    } label: {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.green)
                            Text("Known")
                                .font(.caption)
                        }
                    }
                    Button {
                        keepWord()
                    } label: {
                        VStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.orange)
                            Text("Review again")
                                .font(.caption)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }

    private func flashcard(for word: Word) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
            .overlay {
                VStack(spacing: 20) {
                    Text(word.word)
                        .font(.system(size: 40, weight: .bold))
                        .minimumScaleFactor(0.5)

                    if isRevealed {
                        Divider()
                        if word.definition.isEmpty {
                            Text("Definition unavailable")
                                .foregroundStyle(.secondary)
                                .italic()
                        } else {
                            Text(word.definition)
                                .font(.body)
                                .multilineTextAlignment(.center)
                            if !word.exampleSentence.isEmpty {
                                Text(word.exampleSentence)
                                    .font(.callout)
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        Text(word.sourceLanguage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())
                    }
                }
                .padding(32)
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: 400)
    }

    private func markKnown() {
        withAnimation(.easeInOut) {
            words[currentIndex].isKnown = true
            advance()
        }
    }

    private func keepWord() {
        withAnimation(.easeInOut) {
            advance()
        }
    }

    private func advance() {
        dragOffset = 0
        isRevealed = false
        currentIndex += 1
    }
}

#Preview {
    ReviewView()
        .modelContainer(for: Word.self, inMemory: true)
}
