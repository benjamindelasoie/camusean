import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \Word.timestamp, order: .reverse) private var allWords: [Word]
    @Environment(\.modelContext) private var modelContext

    @State private var filter: LibraryFilter = .all
    @State private var sortMode: LibrarySortMode = .dateAdded
    @State private var searchText: String = ""
    @State private var selectedWord: Word?

    // Display type on the detail sheet — scales with the reader's text-size setting.
    @ScaledMetric(relativeTo: .largeTitle) private var detailWordSize: CGFloat = 36

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
            } else {
                VStack(spacing: 0) {
                    statsHeader
                    filterChips
                    if filteredWords.isEmpty {
                        noMatchesState
                            .frame(maxHeight: .infinity)
                    } else {
                        contentList
                    }
                }
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
                    // Measured at 34.7 x 36pt as a bare Image — under the 44pt floor.
                    Image(systemName: "arrow.up.arrow.down")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Sort")
                }
            }
        }
        .sheet(item: $selectedWord) { word in
            detailSheet(word)
        }
    }

    // MARK: - Grouping by book

    // Once the reader has any book, the Library organizes words under their book (newest book
    // first, "Free reading" last) — "the words I learned reading L'Étranger". Before any book
    // exists, it stays a flat list. Search/filter/sort still apply inside each group.
    private var hasBooks: Bool { allWords.contains { $0.book != nil } }

    private struct BookGroup: Identifiable {
        let id: String
        let title: String
        let words: [Word]
    }

    private var groupedWords: [BookGroup] {
        let grouped = Dictionary(grouping: filteredWords) { $0.book }
        let orderedKeys = grouped.keys.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (l?, r?): return l.dateAdded > r.dateAdded   // newest book first
            case (_?, nil): return true                            // real books before "Free reading"
            case (nil, _?): return false
            case (nil, nil): return false
            }
        }
        return orderedKeys.map { book in
            BookGroup(
                id: book.map { String(describing: $0.persistentModelID) } ?? "free",
                title: book?.title ?? "Free reading",
                words: grouped[book] ?? []
            )
        }
    }

    // MARK: - List

    private var contentList: some View {
        List {
            if hasBooks {
                ForEach(groupedWords) { group in
                    Section(group.title) {
                        ForEach(group.words) { word in rowView(for: word) }
                    }
                }
            } else {
                ForEach(filteredWords) { word in rowView(for: word) }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func rowView(for word: Word) -> some View {
        // A Button, not .onTapGesture: the row carries an accessibility hint promising
        // "double tap for full definition", and only a real button gives VoiceOver the
        // trait to honour it.
        Button { selectedWord = word } label: {
            libraryRow(for: word)
        }
            .buttonStyle(.plain)
            .listRowInsets(.init(top: 12, leading: 20, bottom: 12, trailing: 20))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    delete(word)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func delete(_ word: Word) {
        modelContext.delete(word)
        try? modelContext.save()
    }

    private func libraryRow(for word: Word) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.word)
                    .font(.system(.headline, design: .serif))
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
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
        } else {
            Text("New")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.camuseanText)
                .padding(.horizontal, 8)
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
                .font(.system(.title2, design: .serif).weight(.medium))
                .foregroundStyle(.primary)
            // Was a fixed 9pt, below any reasonable floor and unaffected by the reader's
            // text-size setting.
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label.replacingOccurrences(of: "\n", with: " ").lowercased())")
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(LibraryFilter.allCases) { f in
                Button {
                    filter = f
                } label: {
                    Text(f.rawValue)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        // Was ~30pt tall. 44pt is the HIG floor for anything tappable.
                        .frame(minHeight: 44)
                        .background(filter == f ? Color.camusean : Color(.systemGray6))
                        .foregroundStyle(filter == f ? .white : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == f ? [.isButton, .isSelected] : .isButton)
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
                    .font(.system(.title2, design: .serif).weight(.semibold))
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
                .font(.system(size: detailWordSize, weight: .bold, design: .serif))
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

            VStack(alignment: .leading, spacing: 8) {
                if let bookTitle = word.book?.title {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("From \(bookTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let nrd = word.nextReviewDate {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Next review \(relativeDate(nrd))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
    .modelContainer(for: [Word.self, Book.self], inMemory: true)
}
