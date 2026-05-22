import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \Word.timestamp, order: .reverse) private var allWords: [Word]
    @Environment(\.modelContext) private var modelContext

    @State private var filter: LibraryFilter = .all
    @State private var sortMode: LibrarySortMode = .dateAdded
    @State private var searchText: String = ""
    @State private var selectedWord: Word?

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case due = "Due"
        case scheduled = "Scheduled"
        var id: String { rawValue }
    }

    enum LibrarySortMode: String, CaseIterable, Identifiable {
        case dateAdded = "Date added"
        case alphabetical = "Alphabetical"
        var id: String { rawValue }
    }

    // MARK: - Derived data

    // TODO: switch to dynamic @Query if any user's library exceeds ~5k words. See TODOS.md.
    private var filteredWords: [Word] {
        let now = Date()
        var result = allWords

        if !searchText.isEmpty {
            result = result.filter { $0.word.localizedCaseInsensitiveContains(searchText) }
        }

        switch filter {
        case .all:
            break
        case .due:
            result = result.filter { word in
                guard let nrd = word.nextReviewDate else { return true }
                return nrd <= now
            }
        case .scheduled:
            result = result.filter { word in
                guard let nrd = word.nextReviewDate else { return false }
                return nrd > now
            }
        }

        switch sortMode {
        case .dateAdded:
            result.sort { $0.timestamp > $1.timestamp }
        case .alphabetical:
            result.sort { $0.word.localizedCompare($1.word) == .orderedAscending }
        }

        return result
    }

    private var stats: (total: Int, dueThisWeek: Int, learnedThisWeek: Int) {
        let now = Date()
        let cal = Calendar.current
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let endOfWeek = cal.date(byAdding: .day, value: 7, to: startOfWeek) ?? now

        let total = allWords.count
        let dueThisWeek = allWords.filter { word in
            (word.nextReviewDate ?? now) <= endOfWeek
        }.count
        let learnedThisWeek = allWords.filter { word in
            word.nextReviewDate != nil
                && word.interval >= 6
                && word.timestamp >= startOfWeek
        }.count

        return (total, dueThisWeek, learnedThisWeek)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if allWords.isEmpty {
                emptyState
            } else if filteredWords.isEmpty {
                noMatchesState
            } else {
                contentList
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search words")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(LibrarySortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .accessibilityLabel("Sort")
                }
            }
        }
        .sheet(item: $selectedWord) { word in
            detailSheet(word)
        }
    }

    // MARK: - List

    private var contentList: some View {
        List {
            Section {
                ForEach(filteredWords) { word in
                    libraryRow(for: word)
                        .listRowInsets(.init(top: 12, leading: 20, bottom: 12, trailing: 20))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedWord = word }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(word)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                VStack(spacing: 0) {
                    statsHeader
                    filterChips
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                .textCase(nil)
            }
        }
        .listStyle(.plain)
    }

    private func delete(_ word: Word) {
        modelContext.delete(word)
        try? modelContext.save()
    }

    private func libraryRow(for word: Word) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.word)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .lineLimit(1)

                if !word.definition.isEmpty {
                    Text(word.definition)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            dueDatePill(for: word)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(for: word))
        .accessibilityHint("Double tap for full definition")
    }

    @ViewBuilder
    private func dueDatePill(for word: Word) -> some View {
        if let nrd = word.nextReviewDate {
            Text(relativeDate(nrd))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
        } else {
            Text("New")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.camusean)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.camusean.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - Stats header

    private var statsHeader: some View {
        HStack(spacing: 0) {
            statCell(value: stats.total, label: "TOTAL")
            Divider().frame(height: 28)
            statCell(value: stats.dueThisWeek, label: "DUE THIS\nWEEK")
            Divider().frame(height: 28)
            statCell(value: stats.learnedThisWeek, label: "LEARNED\nTHIS WEEK")
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(LibraryFilter.allCases) { f in
                Button {
                    filter = f
                } label: {
                    Text(f.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(filter == f ? Color.camusean : Color(.systemGray6))
                        .foregroundStyle(filter == f ? .white : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Empty states

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

    private var noMatchesState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray6))
                    .frame(width: 100, height: 100)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color(.systemGray2))
            }
            VStack(spacing: 8) {
                Text("No matches")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                Text(searchText.isEmpty
                     ? "No words in this filter."
                     : "No words match \u{201C}\(searchText)\u{201D}.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }

    // MARK: - Detail sheet

    @ViewBuilder
    private func detailSheet(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(word.word)
                .font(.system(size: 36, weight: .bold, design: .serif))
                .padding(.top, 8)

            if !word.definition.isEmpty {
                Text(word.definition)
                    .font(.body)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineSpacing(4)
            } else {
                Text("Definition unavailable")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            if !word.exampleSentence.isEmpty {
                Text(word.exampleSentence)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            Spacer()

            if let nrd = word.nextReviewDate {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text("Next review \(relativeDate(nrd))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func rowAccessibilityLabel(for word: Word) -> String {
        var parts = [word.word]
        if !word.definition.isEmpty {
            parts.append(word.definition)
        }
        if let nrd = word.nextReviewDate {
            parts.append("due \(relativeDate(nrd))")
        } else {
            parts.append("new, due now")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .modelContainer(for: Word.self, inMemory: true)
}
