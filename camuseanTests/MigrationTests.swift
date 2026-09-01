import Foundation
import Testing
import SwiftData
@testable import camusean

// Tests the V1 -> V2 migration mapping directly via CamuseanMigrationPlan.applyV1toV2Mapping
// (the same closure the production stage runs) because the full SwiftData roundtrip fails in test
// harnesses with `loadIssueModelContainer`: the V1 container is held alive by SwiftData's
// process-level store registry even after going out of scope.
@MainActor
@Suite struct MigrationTests {

    // Rows inserted here stand in for V1 rows post-lightweight-rename: same fields, new SRS
    // columns at their defaults.
    private func makeV2Container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CamuseanSchemaV2.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // An isKnown=true row must land on a future schedule so it does NOT resurface in Review.
    @Test func isKnownTrueRowMigratesToFutureSchedule() throws {
        let container = try makeV2Container()
        let context = ModelContext(container)

        let row = CamuseanSchemaV2.Word(
            word: "bonjour",
            definition: "hello",
            exampleSentence: "Bonjour, comment ça va?",
            sourceLanguage: "French",
            targetLanguage: "English"
        )
        row.isKnown = true
        context.insert(row)
        try context.save()

        let migrationNow = Date(timeIntervalSince1970: 1_800_000_000)
        try CamuseanMigrationPlan.applyV1toV2Mapping(in: context, now: migrationNow)

        let result = try context.fetch(FetchDescriptor<CamuseanSchemaV2.Word>())
        try #require(result.count == 1)
        let migrated = result[0]
        #expect(migrated.word == "bonjour")
        #expect(migrated.isKnown == true) // legacy field retained
        #expect(migrated.interval == 365)
        #expect(abs(migrated.easeFactor - 2.5) < 0.0001)
        let expected = Calendar.current.date(byAdding: .day, value: 365, to: migrationNow)
        #expect(migrated.nextReviewDate == expected)
    }

    // An isKnown=false row must keep nextReviewDate=nil so it still appears in Review (it was
    // due under v1.0, still due).
    @Test func isKnownFalseRowMigratesAsDue() throws {
        let container = try makeV2Container()
        let context = ModelContext(container)

        let row = CamuseanSchemaV2.Word(
            word: "flâner",
            sourceLanguage: "French",
            targetLanguage: "English"
        )
        row.isKnown = false
        context.insert(row)
        try context.save()

        try CamuseanMigrationPlan.applyV1toV2Mapping(in: context, now: Date())

        let result = try context.fetch(FetchDescriptor<CamuseanSchemaV2.Word>())
        try #require(result.count == 1)
        let migrated = result[0]
        #expect(migrated.word == "flâner")
        #expect(migrated.isKnown == false)
        #expect(migrated.interval == 0)
        #expect(abs(migrated.easeFactor - 2.5) < 0.0001)
        #expect(migrated.nextReviewDate == nil)
    }

    @Test func nonSRSFieldsPreservedVerbatim() throws {
        let container = try makeV2Container()
        let context = ModelContext(container)

        let frozenTimestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let row = CamuseanSchemaV2.Word(
            word: "désinvolture",
            definition: "casualness, nonchalance",
            exampleSentence: "Il répondit avec désinvolture.",
            sourceLanguage: "French",
            targetLanguage: "English"
        )
        row.timestamp = frozenTimestamp
        row.isKnown = true
        context.insert(row)
        try context.save()

        try CamuseanMigrationPlan.applyV1toV2Mapping(in: context, now: Date())

        let result = try context.fetch(FetchDescriptor<CamuseanSchemaV2.Word>())
        try #require(result.count == 1)
        let migrated = result[0]
        #expect(migrated.word == "désinvolture")
        #expect(migrated.definition == "casualness, nonchalance")
        #expect(migrated.exampleSentence == "Il répondit avec désinvolture.")
        #expect(migrated.sourceLanguage == "French")
        #expect(migrated.targetLanguage == "English")
        #expect(migrated.timestamp == frozenTimestamp)
        #expect(migrated.isKnown == true)
    }
}
