import Foundation
import Testing
import SwiftData
@testable import camusean

// V4 schema coverage. A lightweight migration stage has no mapping closure to unit-test, so the
// risk it carries is a malformed schema/relationship that only blows up at container init or on
// delete. These tests build a real in-memory V4 container and prove: the schema is valid, the
// Book<->Word relationship round-trips, and — critically — deleting a Book NULLIFIES its words
// rather than cascade-deleting a reader's vocabulary.
@MainActor
@Suite struct BookSchemaV4Tests {

    private func makeV4Context() throws -> ModelContext {
        let schema = Schema(versionedSchema: CamuseanSchemaV4.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // The V4 container opens at all (the schema + relationship are well-formed) and a Book with
    // its future-ready identity fields round-trips.
    @Test func v4ContainerOpensAndBookRoundTrips() throws {
        let context = try makeV4Context()
        let book = Book(
            title: "L'Étranger",
            author: "Albert Camus",
            language: "fr-FR",
            isbn: "9782070360024",
            openLibraryEditionID: "OL12345M",
            openLibraryWorkID: "OL67890W",
            coverURL: "https://covers.openlibrary.org/b/id/1.jpg"
        )
        context.insert(book)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Book>())
        try #require(fetched.count == 1)
        let b = fetched[0]
        #expect(b.title == "L'Étranger")
        #expect(b.author == "Albert Camus")
        #expect(b.language == "fr-FR")
        #expect(b.isbn == "9782070360024")
        #expect(b.openLibraryEditionID == "OL12345M")
        #expect(b.openLibraryWorkID == "OL67890W")
        #expect(b.dateFinished == nil)
        #expect(b.words.isEmpty)
    }

    // A Word can be book-tied or free (nil book), and the inverse relationship populates both ways.
    @Test func wordBookRelationshipRoundTripsBothWays() throws {
        let context = try makeV4Context()
        let book = Book(title: "Madame Bovary", author: "Gustave Flaubert", language: "fr-FR")
        context.insert(book)

        let tied = Word(word: "désinvolture", sourceLanguage: "French", targetLanguage: "English", book: book)
        let free = Word(word: "flâner", sourceLanguage: "French", targetLanguage: "English")
        context.insert(tied)
        context.insert(free)
        try context.save()

        // to-one side
        #expect(tied.book?.title == "Madame Bovary")
        #expect(free.book == nil)
        // to-many inverse populated automatically
        #expect(book.words.count == 1)
        #expect(book.words.first?.word == "désinvolture")
    }

    // CRITICAL: deleting a Book must NULLIFY its words (preserve the vocabulary), never cascade.
    @Test func deletingBookNullifiesWordsRatherThanCascading() throws {
        let context = try makeV4Context()
        let book = Book(title: "Le Petit Prince", author: "Antoine de Saint-Exupéry", language: "fr-FR")
        context.insert(book)
        let tied = Word(word: "apprivoiser", sourceLanguage: "French", targetLanguage: "English", book: book)
        let free = Word(word: "renard", sourceLanguage: "French", targetLanguage: "English")
        context.insert(tied)
        context.insert(free)
        try context.save()

        context.delete(book)
        try context.save()

        // Both words survive — the reader's vocabulary is intact.
        let words = try context.fetch(FetchDescriptor<Word>())
        #expect(words.count == 2)
        // The formerly-tied word's back-reference is nullified, not dangling.
        let apprivoiser = try #require(words.first { $0.word == "apprivoiser" })
        #expect(apprivoiser.book == nil)
        // The book is gone.
        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.isEmpty)
    }

    // originalTranscription persists for corrected words and is nil otherwise.
    @Test func originalTranscriptionPersists() throws {
        let context = try makeV4Context()
        let corrected = Word(
            word: "livre",
            sourceLanguage: "French",
            targetLanguage: "English",
            originalTranscription: "leevr"
        )
        let uncorrected = Word(word: "bonjour", sourceLanguage: "French", targetLanguage: "English")
        context.insert(corrected)
        context.insert(uncorrected)
        try context.save()

        let words = try context.fetch(FetchDescriptor<Word>())
        let livre = try #require(words.first { $0.word == "livre" })
        let bonjour = try #require(words.first { $0.word == "bonjour" })
        #expect(livre.originalTranscription == "leevr")
        #expect(bonjour.originalTranscription == nil)
    }

    // v1.5: formNote persists for an inflected form and stays nil for a plain dictionary word.
    // nil is the same state every pre-V4 row migrates to, so this also covers what an existing
    // reader's library looks like immediately after the V3 -> V4 lightweight stage runs.
    @Test func formNotePersistsAndDefaultsToNil() throws {
        let context = try makeV4Context()
        let inflected = Word(
            word: "disparu",
            sourceLanguage: "French",
            targetLanguage: "English",
            formNote: "Past participle of disparaître"
        )
        let plain = Word(word: "livre", sourceLanguage: "French", targetLanguage: "English")
        context.insert(inflected)
        context.insert(plain)
        try context.save()

        let words = try context.fetch(FetchDescriptor<Word>())
        let disparu = try #require(words.first { $0.word == "disparu" })
        let livre = try #require(words.first { $0.word == "livre" })
        #expect(disparu.formNote == "Past participle of disparaître")
        #expect(livre.formNote == nil)
    }
}
