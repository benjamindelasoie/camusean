import Testing
import Foundation
@testable import camusean

// Search, filter, and sort for the Library. Previously private computed properties inside
// LibraryView and therefore untestable.
@Suite("Library query")
struct LibraryQueryTests {

    private func word(
        _ text: String,
        definition: String = "",
        nextReview: Date? = nil,
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Word {
        let w = Word(
            word: text, definition: definition, exampleSentence: "",
            sourceLanguage: "French", targetLanguage: "English"
        )
        w.nextReviewDate = nextReview
        w.timestamp = timestamp
        return w
    }

    // MARK: - Search

    @Test func searchMatchesTheDefinition() {
        // The case the old implementation could not serve at all: you remember the English,
        // not the French.
        let fenetre = word("fenêtre", definition: "window; an opening in a wall")
        #expect(LibraryQuery.matches(fenetre, search: "window"))
    }

    @Test func searchMatchesTheHeadword() {
        #expect(LibraryQuery.matches(word("fenêtre", definition: "window"), search: "fen"))
    }

    @Test func searchIgnoresCase() {
        #expect(LibraryQuery.matches(word("Fenêtre", definition: "window"), search: "FENÊTRE"))
    }

    @Test func searchIgnoresDiacritics() {
        // Typing the circumflex is the exception, not the rule.
        #expect(LibraryQuery.matches(word("fenêtre", definition: "window"), search: "fenetre"))
    }

    @Test func emptyAndWhitespaceSearchMatchesEverything() {
        let w = word("fenêtre", definition: "window")
        #expect(LibraryQuery.matches(w, search: ""))
        #expect(LibraryQuery.matches(w, search: "   "))
    }

    @Test func emptyDefinitionDoesNotMatchEverything() {
        // API-failure rows persist with an empty definition; they must not match every query.
        #expect(!LibraryQuery.matches(word("fenêtre", definition: ""), search: "window"))
    }

    @Test func nonMatchingSearchFindsNothing() {
        #expect(!LibraryQuery.matches(word("fenêtre", definition: "window"), search: "zebra"))
    }

    // MARK: - Filter

    @Test func dueFilterKeepsOnlyDueWords() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = LibraryQuery.apply(
            to: [
                word("new"),
                word("later", nextReview: now.addingTimeInterval(86_400)),
                word("overdue", nextReview: now.addingTimeInterval(-86_400)),
            ],
            search: "", filter: .due, sort: .alphabetical, now: now
        )
        #expect(result.map(\.word) == ["new", "overdue"])
    }

    @Test func scheduledFilterIsTheExactComplementOfDue() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let words = [
            word("new"),
            word("later", nextReview: now.addingTimeInterval(86_400)),
            word("overdue", nextReview: now.addingTimeInterval(-86_400)),
        ]
        let due = LibraryQuery.apply(to: words, search: "", filter: .due, sort: .alphabetical, now: now)
        let scheduled = LibraryQuery.apply(to: words, search: "", filter: .scheduled, sort: .alphabetical, now: now)
        #expect(due.count + scheduled.count == words.count)
        #expect(Set(due.map(\.word)).isDisjoint(with: Set(scheduled.map(\.word))))
    }

    // MARK: - Sort

    @Test func alphabeticalSortIsLocaleAware() {
        let result = LibraryQuery.apply(
            to: [word("zèbre"), word("abricot"), word("Éclair")],
            search: "", filter: .all, sort: .alphabetical
        )
        #expect(result.map(\.word) == ["abricot", "Éclair", "zèbre"])
    }

    @Test func dateAddedSortIsNewestFirst() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let result = LibraryQuery.apply(
            to: [
                word("old", timestamp: base),
                word("new", timestamp: base.addingTimeInterval(1000)),
            ],
            search: "", filter: .all, sort: .dateAdded
        )
        #expect(result.map(\.word) == ["new", "old"])
    }

    // MARK: - Search and filter compose

    @Test func searchAndFilterApplyTogether() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = LibraryQuery.apply(
            to: [
                word("fenêtre", definition: "window"),
                word("porte", definition: "door", nextReview: now.addingTimeInterval(86_400)),
                word("vitre", definition: "window pane", nextReview: now.addingTimeInterval(86_400)),
            ],
            search: "window", filter: .due, sort: .alphabetical, now: now
        )
        // "vitre" matches the search but is not due; "porte" is neither.
        #expect(result.map(\.word) == ["fenêtre"])
    }
}
