import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \Word.timestamp, order: .reverse) private var allWords: [Word]
    @Environment(\.modelContext) private var modelContext

    @State private var filter: LibraryFilter = .all
    @State private var sortMode: LibrarySortMode = .dateAdded
    @State private var searchText: String = ""
    @State private var selectedWord: Word?

    // MARK: - Body

    // Everything derived is computed ONCE here and handed down. Reading a computed property
    // re-runs it every time, and the previous shape read `filteredWords` (filter + sort) at
    // least twice per render plus three separate passes for the stats.
    //
    // TODO: switch to dynamic @Query if any user's library exceeds ~5k words. See TODOS.md.
    var body: some View {
        let now = Date()
        let filtered = LibraryQuery.apply(
            to: allWords, search: searchText, filter: filter, sort: sortMode, now: now
        )
        let stats = LibraryStats.compute(for: allWords, now: now)
        let groups = LibraryQuery.hasBooks(allWords)
            ? LibraryQuery.group(filtered: filtered, allWords: allWords, now: now)
            : []

        return Group {
            if allWords.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    statsHeader(stats)
                    filterChips
                    if filtered.isEmpty {
                        noMatchesState
                            .frame(maxHeight: .infinity)
                    } else {
                        contentList(filtered: filtered, groups: groups)
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
            WordDetailSheet(word: word)
        }
    }

    // MARK: - List

    // Once the reader has any book, the Library organizes words under their book (newest book
    // first, "Free reading" last) — "the words I learned reading L'Étranger". Before any book
    // exists, it stays a flat list. Search/filter/sort still apply inside each group; the
    // section header counts describe the whole book (see LibraryQuery.BookGroup).
    private func contentList(filtered: [Word], groups: [LibraryQuery.BookGroup]) -> some View {
        List {
            if groups.isEmpty {
                ForEach(filtered) { word in rowView(for: word) }
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.words) { word in rowView(for: word) }
                    } header: {
                        bookSectionHeader(group)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func bookSectionHeader(_ group: LibraryQuery.BookGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.title)
            Spacer()
            // Counts describe the BOOK, not the filtered rows below — otherwise a search
            // would leave the header disagreeing with what's on screen for no visible reason.
            Text("\(group.totalInBook) · \(group.matureInBook) at \(WordScheduleRules.matureIntervalDays)+ days")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(group.title), \(group.totalInBook) words, "
            + "\(group.matureInBook) scheduled at \(WordScheduleRules.matureIntervalDays) days or more"
        )
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

    // Three non-overlapping facts. The previous set (total / due this week / learned this
    // week) routinely rendered "29 / 29 / 0" — two identical numbers and a zero — because
    // "total" and "due this week" describe almost the same thing on a young library.
    //
    // "AT 21+ DAYS" is deliberately not labelled "mastered": one lapse resets the interval
    // to a single day, and with no review history the app cannot claim a word was ever
    // previously mature. The label states what is actually true.
    private func statsHeader(_ stats: LibraryStats) -> some View {
        HStack(spacing: 0) {
            statCell(value: stats.dueNow, label: "DUE NOW")
            Divider().frame(height: 28)
            statCell(value: stats.learning, label: "LEARNING")
            Divider().frame(height: 28)
            statCell(value: stats.mature, label: "AT \(WordScheduleRules.matureIntervalDays)+\nDAYS")
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
        EmptyStateView(
            systemImage: "books.vertical",
            title: "No words yet",
            message: "Start a reading session\nto build your vocabulary."
        )
    }

    private var noMatchesState: some View {
        EmptyStateView(
            systemImage: "magnifyingglass",
            title: "No matches",
            message: searchText.isEmpty
                ? "No words in this filter."
                : "No words match \u{201C}\(searchText)\u{201D}."
        )
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
