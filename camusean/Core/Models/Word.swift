import Foundation
import SwiftData

// `models` entries are qualified with `Self.` deliberately: a bare `Word.self` resolves to the
// file-scope typealias (the current schema), which would make a frozen version migrate against the
// wrong shape.

// V2 (v1.1): adds SM-2 SRS fields to V1. Frozen snapshot for the migration plan.
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
        // Deprecated (use SRS fields) but kept on disk for back-compat.
        var isKnown: Bool

        // SM-2 state. nextReviewDate == nil means "due now".
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

// V3 (v1.4): adds the `Book` entity plus optional `Word.book` and `Word.originalTranscription`.
// Additive/optional, so V2 -> V3 is lightweight. FROZEN — shipped to a device with real rows, so
// editing it in place would mutate a schema version already on disk.
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
        // Deprecated (use SRS fields) but kept on disk for back-compat.
        var isKnown: Bool

        // SM-2 state. nextReviewDate == nil means "due now".
        var interval: Int = 0
        var easeFactor: Double = 2.5
        var nextReviewDate: Date? = nil

        // nil for free sessions and every pre-V3 row. The to-one side; the inverse + nullify rule
        // live on `Book.words`.
        var book: Book? = nil

        // Raw ASR text when the LLM corrected a mishearing (nil otherwise). Persisted so the
        // false-correction rate survives restarts and stays queryable.
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

        // Stable identity / future join keys. All optional — a manual add may have none.
        var isbn: String?
        var openLibraryEditionID: String?
        var openLibraryWorkID: String?
        var coverURL: String?

        var dateAdded: Date
        // Reserved for v1.5 progress; nil until the book is marked finished.
        var dateFinished: Date?

        // Nullify, never cascade — deleting a book must not delete a reader's saved words. Only
        // side that declares the relationship; `Word.book` is inferred from the inverse keypath.
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

// V4 (v1.5): adds optional `Word.formNote` — the morphology/lemma line shown on screen but never
// spoken. Its own field rather than folded into `definition` because the definition is English-only
// and spoken aloud, where a French lemma gets mangled by the en-US voice. Additive/optional, so
// V3 -> V4 is lightweight. `Book` is re-declared unchanged (a versioned schema must list every model).
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
        // Deprecated (use SRS fields) but kept on disk for back-compat.
        var isKnown: Bool

        // SM-2 state. nextReviewDate == nil means "due now".
        var interval: Int = 0
        var easeFactor: Double = 2.5
        var nextReviewDate: Date? = nil

        // nil for free sessions.
        var book: Book? = nil

        // Raw ASR text when the LLM corrected a mishearing.
        var originalTranscription: String? = nil

        // Morphology/lemma teaching, displayed but never passed to TTS. nil when nothing to teach.
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

        // Stable identity / future join keys. All optional — a manual add may have none.
        var isbn: String?
        var openLibraryEditionID: String?
        var openLibraryWorkID: String?
        var coverURL: String?

        var dateAdded: Date
        // Reserved for v1.5 progress; nil until the book is marked finished.
        var dateFinished: Date?

        // Nullify, never cascade — deleting a book must not delete a reader's saved words. Only
        // side that declares the relationship; `Word.book` is inferred from the inverse keypath.
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

// Canonical app types — the current schema version.
typealias Word = CamuseanSchemaV4.Word
typealias Book = CamuseanSchemaV4.Book
