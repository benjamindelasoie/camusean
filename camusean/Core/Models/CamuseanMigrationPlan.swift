import Foundation
import SwiftData

// V1: the v1.0 schema. Snapshot of the old Word shape with no SRS fields.
enum CamuseanSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Self.Word.self] }

    @Model
    final class Word {
        var word: String
        var definition: String
        var exampleSentence: String
        var sourceLanguage: String
        var targetLanguage: String
        var timestamp: Date
        var isKnown: Bool

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
        }
    }
}

enum CamuseanMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CamuseanSchemaV1.self, CamuseanSchemaV2.self, CamuseanSchemaV3.self, CamuseanSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
    }

    // V3 -> V4: adds the optional `Word.formNote`. Additive with a property-level default, so it
    // is lightweight with no mapping closure — existing rows simply get nil and display no form
    // note, which is the same as a word that teaches nothing extra.
    //
    // V3 shipped to a real device with real rows, so `formNote` could NOT be added to V3 in place;
    // that would mutate a schema version already on disk and risks the same class of failure as
    // the v1.1 `easeFactor` crash ("missing attribute values on mandatory destination attribute").
    // Any future persisted field needs its own version + stage for the same reason.
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: CamuseanSchemaV3.self,
        toVersion: CamuseanSchemaV4.self
    )

    // V2 -> V3: purely additive (new optional `Word.book`/`Word.originalTranscription` and the new
    // `Book` entity), so this is a lightweight stage with no mapping closure. Do NOT model it on
    // the custom V1 -> V2 stage above — there is no per-row logic to run, and a custom stage here
    // would be needless risk. Registering it (and adding V3 to `schemas`) is mandatory: without
    // the stage SwiftData sees two schema versions with no path between them and throws at
    // container init.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: CamuseanSchemaV2.self,
        toVersion: CamuseanSchemaV3.self
    )

    // V1 -> V2: existing rows where isKnown==true get parked on a future schedule so they don't
    // resurface in Review. Rows where isKnown==false get nextReviewDate=nil and reappear as due,
    // matching v1.0 behavior. New rows after migration go through Word.init defaults.
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: CamuseanSchemaV1.self,
        toVersion: CamuseanSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            try applyV1toV2Mapping(in: context, now: Date())
        }
    )

    // Extracted so tests can invoke the mapping logic directly against a V2 context
    // without depending on SwiftData's process-level migration machinery.
    static func applyV1toV2Mapping(in context: ModelContext, now: Date) throws {
        let descriptor = FetchDescriptor<CamuseanSchemaV2.Word>()
        let words = try context.fetch(descriptor)
        let oneYearOut = Calendar.current.date(byAdding: .day, value: 365, to: now)
        for word in words where word.isKnown {
            word.interval = 365
            word.easeFactor = 2.5
            word.nextReviewDate = oneYearOut
        }
        try context.save()
    }
}
