import Foundation
import SwiftData

// Searching, filtering, sorting, and grouping the Library. Pure functions over `[Word]` — these
// were `private` computed properties inside `LibraryView`, out of the test target's reach and
// re-run by SwiftUI on every access. Compute once, pass down.

enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case due = "Due"
    case scheduled = "Scheduled"
    var id: String { rawValue }
}

enum LibrarySortMode: String, CaseIterable, Identifiable, Sendable {
    case dateAdded = "Date added"
    case alphabetical = "Alphabetical"
    var id: String { rawValue }
}

enum LibraryQuery {
    /// Matches a search term against the headword AND its definition.
    ///
    /// Definition matching is the point: the common failure is remembering the English, not the
    /// French — searching "window" could not otherwise find *fenêtre*. `localizedStandardContains`
    /// is case- and diacritic-insensitive, so "fenetre" finds *fenêtre* (the accent may not be on
    /// the keyboard).
    static func matches(_ word: Word, search: String) -> Bool {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return word.word.localizedStandardContains(term)
            || word.definition.localizedStandardContains(term)
    }

    static func apply(
        to words: [Word],
        search: String,
        filter: LibraryFilter,
        sort: LibrarySortMode,
        now: Date = Date()
    ) -> [Word] {
        var result = words.filter { matches($0, search: search) }

        switch filter {
        case .all:
            break
        case .due:
            result = result.filter { WordScheduleRules.isDue($0, now: now) }
        case .scheduled:
            result = result.filter { !WordScheduleRules.isDue($0, now: now) }
        }

        switch sort {
        case .dateAdded:
            result.sort { $0.timestamp > $1.timestamp }
        case .alphabetical:
            result.sort { $0.word.localizedCompare($1.word) == .orderedAscending }
        }

        return result
    }

    /// A book's section in the Library, with counts.
    ///
    /// `totalInBook`/`matureInBook` count the whole book, not the filtered subset in `words`: the
    /// header describes the book, the rows describe the filter. Otherwise a "12 words" header over
    /// four rows under an active search would look like a bug.
    struct BookGroup: Identifiable, Sendable {
        let id: String
        let title: String
        let words: [Word]
        let totalInBook: Int
        let matureInBook: Int
    }

    /// Groups the (already filtered) words under their book, newest book first, free reading last.
    /// `allWords` is needed unfiltered so the per-book totals describe the book, not the search.
    static func group(
        filtered: [Word],
        allWords: [Word],
        now: Date = Date()
    ) -> [BookGroup] {
        let grouped = Dictionary(grouping: filtered) { $0.book }
        let orderedKeys = grouped.keys.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (l?, r?): return l.dateAdded > r.dateAdded   // newest book first
            case (_?, nil): return true                            // real books before "Free reading"
            case (nil, _?): return false
            case (nil, nil): return false
            }
        }

        return orderedKeys.map { book in
            let inBook = allWords.filter { $0.book?.persistentModelID == book?.persistentModelID }
            return BookGroup(
                id: book.map { String(describing: $0.persistentModelID) } ?? "free",
                title: book?.title ?? "Free reading",
                words: grouped[book] ?? [],
                totalInBook: inBook.count,
                matureInBook: inBook.filter { WordScheduleRules.progress(for: $0, now: now).isMature }.count
            )
        }
    }

    static func hasBooks(_ words: [Word]) -> Bool {
        words.contains { $0.book != nil }
    }
}
