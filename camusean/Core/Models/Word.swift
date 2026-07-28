import Foundation
import SwiftData

// Each version's `models` array qualifies its entries with `Self.` on purpose. A bare `Word.self`
// inside these enums does resolve to the nested type (an inner declaration shadows the file-scope
// typealias), but the two names are only one scoping rule apart, and a version that silently
// listed the CURRENT `Word` would break its own migration. The explicit form is the documented
// convention for exactly this ambiguity.

// V2: the v1.1 schema (adds SM-2 SRS fields to V1). Kept as a frozen snapshot for the
// migration plan; V3 below is the current schema (see the typealiases at the bottom).
enum CamuseanSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Self.Word.self] }

    @Model
    final class Word {
        var word: String
        var definition: String
        var exampleSentence: String
        var sourceLanguage: String
        var targetLanguage: String
        var timestamp: Date
        // isKnown is deprecated in v1.1 (use SRS fields below) but kept on disk for backwards compat.
        var isKnown: Bool

        // SM-2 scheduling state. nextReviewDate == nil means "due now" (new word or post-lapse).
        var interval: Int = 0
        var easeFactor: Double = 2.5
        var nextReviewDate: Date? = nil

        init(
            word: String,
            definition: String = "",
            exampleSentence: String = "",
            sourceLanguage: String,
            targetLanguage: String
        ) {
            self.word = word
            self.definition = definition
            self.exampleSentence = exampleSentence
            self.sourceLanguage = sourceLanguage
            self.targetLanguage = targetLanguage
            self.timestamp = Date()
            self.isKnown = false
            self.interval = 0
            self.easeFactor = 2.5
            self.nextReviewDate = nil
        }
    }
}

// V3: the v1.4 schema. Adds the `Book` entity (the app's organizing spine) and two optional
// fields on `Word` — `book` (the book a word was learned in) and `originalTranscription` (the
// raw ASR text when the LLM corrected a misheard word). All additions are additive and
// optional/defaulted, so V2 -> V3 is a lightweight migration (see CamuseanMigrationPlan).
//
// FROZEN. V3 shipped to a real device with real saved rows, so editing it in place would change
// a schema version that already exists on disk. V4 below is the current schema.
enum CamuseanSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] { [Self.Word.self, Self.Book.self] }

    @Model
    final class Word {
        var word: String
        var definition: String
        var exampleSentence: String
        var sourceLanguage: String
        var targetLanguage: String
        var timestamp: Date
        // isKnown is deprecated (use SRS fields) but kept on disk for backwards compat.
        var isKnown: Bool

        // SM-2 scheduling state. nextReviewDate == nil means "due now".
        var interval: Int = 0
        var easeFactor: Double = 2.5
        var nextReviewDate: Date? = nil

        // v1.4: the book this word was learned in. nil for free sessions and for every row that
        // existed before V3. The to-one side; the inverse + delete rule live on `Book.words`.
        var book: Book? = nil

        // v1.4: the raw speech transcription when the LLM corrected a likely mishearing (nil when
        // no correction happened). Lets the false-correction rate survive restarts and be queryable
        // instead of living only in console logs.
        var originalTranscription: String? = nil

        init(
            word: String,
            definition: String = "",
            exampleSentence: String = "",
            sourceLanguage: String,
            targetLanguage: String,
            book: Book? = nil,
            originalTranscription: String? = nil
        ) {
            self.word = word
            self.definition = definition
            self.exampleSentence = exampleSentence
            self.sourceLanguage = sourceLanguage
            self.targetLanguage = targetLanguage
            self.timestamp = Date()
            self.isKnown = false
            self.interval = 0
            self.easeFactor = 2.5
            self.nextReviewDate = nil
            self.book = book
            self.originalTranscription = originalTranscription
        }
    }

    @Model
    final class Book {
        var title: String
        var author: String
        // Source-language locale resolved at add time (e.g. "fr-FR"). May be empty until the user
        // picks one — Open Library's language coverage on foreign editions is uneven.
        var language: String

        // Stable identity / future join keys (Hardcover, progress, catalog sync). All optional —
        // a manually-added book may have none of them.
        var isbn: String?
        var openLibraryEditionID: String?
        var openLibraryWorkID: String?
        var coverURL: String?

        var dateAdded: Date
        // Reserved for v1.5 progress tracking; nil until the reader marks the book finished.
        var dateFinished: Date?

        // Deleting a book NULLIFIES its words' back-reference — it must never cascade-delete a
        // reader's saved vocabulary. This is the only side that declares the relationship; the
        // `Word.book` to-one side is inferred from the `inverse:` keypath.
        @Relationship(deleteRule: .nullify, inverse: \Word.book)
        var words: [Word] = []

        init(
            title: String,
            author: String = "",
            language: String = "",
            isbn: String? = nil,
            openLibraryEditionID: String? = nil,
            openLibraryWorkID: String? = nil,
            coverURL: String? = nil,
            dateAdded: Date = Date(),
            dateFinished: Date? = nil
        ) {
            self.title = title
            self.author = author
            self.language = language
            self.isbn = isbn
            self.openLibraryEditionID = openLibraryEditionID
            self.openLibraryWorkID = openLibraryWorkID
            self.coverURL = coverURL
            self.dateAdded = dateAdded
            self.dateFinished = dateFinished
        }
    }
}

// V4: adds `Word.formNote` — the morphology/lemma teaching line ("Past participle of
// *disparaître*", "Feminine of *fatigué*"), shown on screen but never spoken. It exists as its
// own field rather than folded into `definition` because the definition is now English-only and
// spoken aloud: a French lemma inside it would be mangled by the en-US voice (the observed
// "chansons" -> "plural of chanson" bug). nil for a plain word that teaches nothing extra.
//
// Additive and optional, so V3 -> V4 is a lightweight migration. `Book` is carried over
// unchanged — a versioned schema must declare every model it contains, so it is re-declared
// here rather than reused from V3.
enum CamuseanSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] { [Self.Word.self, Self.Book.self] }

    @Model
    final class Word {
        var word: String
        var definition: String
        var exampleSentence: String
        var sourceLanguage: String
        var targetLanguage: String
        var timestamp: Date
        // isKnown is deprecated (use SRS fields) but kept on disk for backwards compat.
        var isKnown: Bool

        // SM-2 scheduling state. nextReviewDate == nil means "due now".
        var interval: Int = 0
        var easeFactor: Double = 2.5
        var nextReviewDate: Date? = nil

        // v1.4: the book this word was learned in. nil for free sessions.
        var book: Book? = nil

        // v1.4: the raw speech transcription when the LLM corrected a likely mishearing.
        var originalTranscription: String? = nil

        // v1.5: morphology/lemma teaching, displayed but NEVER passed to TTS. nil when the word
        // is its own dictionary form and there is nothing to teach.
        var formNote: String? = nil

        init(
            word: String,
            definition: String = "",
            exampleSentence: String = "",
            sourceLanguage: String,
            targetLanguage: String,
            book: Book? = nil,
            originalTranscription: String? = nil,
            formNote: String? = nil
        ) {
            self.word = word
            self.definition = definition
            self.exampleSentence = exampleSentence
            self.sourceLanguage = sourceLanguage
            self.targetLanguage = targetLanguage
            self.timestamp = Date()
            self.isKnown = false
            self.interval = 0
            self.easeFactor = 2.5
            self.nextReviewDate = nil
            self.book = book
            self.originalTranscription = originalTranscription
            self.formNote = formNote
        }
    }

    @Model
    final class Book {
        var title: String
        var author: String
        // Source-language locale resolved at add time (e.g. "fr-FR"). May be empty until the user
        // picks one — Open Library's language coverage on foreign editions is uneven.
        var language: String

        // Stable identity / future join keys (Hardcover, progress, catalog sync). All optional —
        // a manually-added book may have none of them.
        var isbn: String?
        var openLibraryEditionID: String?
        var openLibraryWorkID: String?
        var coverURL: String?

        var dateAdded: Date
        // Reserved for v1.5 progress tracking; nil until the reader marks the book finished.
        var dateFinished: Date?

        // Deleting a book NULLIFIES its words' back-reference — it must never cascade-delete a
        // reader's saved vocabulary. This is the only side that declares the relationship; the
        // `Word.book` to-one side is inferred from the `inverse:` keypath.
        @Relationship(deleteRule: .nullify, inverse: \Word.book)
        var words: [Word] = []

        init(
            title: String,
            author: String = "",
            language: String = "",
            isbn: String? = nil,
            openLibraryEditionID: String? = nil,
            openLibraryWorkID: String? = nil,
            coverURL: String? = nil,
            dateAdded: Date = Date(),
            dateFinished: Date? = nil
        ) {
            self.title = title
            self.author = author
            self.language = language
            self.isbn = isbn
            self.openLibraryEditionID = openLibraryEditionID
            self.openLibraryWorkID = openLibraryWorkID
            self.coverURL = coverURL
            self.dateAdded = dateAdded
            self.dateFinished = dateFinished
        }
    }
}

// Canonical app types — always the current schema version.
typealias Word = CamuseanSchemaV4.Word
typealias Book = CamuseanSchemaV4.Book
