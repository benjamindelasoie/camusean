import Foundation
import SwiftData

// Current schema. V1 lives in CamuseanMigrationPlan.swift alongside the migration stage.
enum CamuseanSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Word.self] }

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
        // Property defaults are required for SwiftData lightweight migration: when v1.0
        // rows are migrated to V2, these fields must have schema-level defaults or
        // CoreData errors with "missing attribute values on mandatory destination attribute".
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

typealias Word = CamuseanSchemaV2.Word
