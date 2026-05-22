import Foundation
import Testing
import SwiftData
@testable import camusean

// Tests for the V1 -> V2 migration MAPPING. SwiftData's in-process migration roundtrip
// (open V1, write, reopen V2 + plan) fails in test harnesses with
// `loadIssueModelContainer` because the V1 container is held alive by SwiftData's
// process-level store registry even after going out of scope. So we test the mapping
// logic directly via CamuseanMigrationPlan.applyV1toV2Mapping, which is the same
// closure body the production migration stage runs. This covers OUR logic; the
// SwiftData schema-version detection itself is Apple's responsibility.
@MainActor
@Suite struct MigrationTests {

    // Build an in-memory V2 container. New rows here simulate the post-lightweight-rename
    // state of rows previously persisted under V1 — same fields, new SRS columns at defaults.
    private func makeV2Container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CamuseanSchemaV2.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // 1. CRITICAL: a row where isKnown=true must land on a future schedule
    //    (interval=365, EF=2.5, nextReviewDate≈now+365d) so it does NOT resurface in Review.
    @Test func isKnownTrueRowMigratesToFutureSchedule() throws {
        let container = try makeV2Container()
        let context = ModelContext(container)

        let row = Word(
            word: "bonjour",
            definition: "hello",
            exampleSentence: "Bonjour, comment ça va?",
            sourceLanguage: "French",
            targetLanguage: "English"
        )
        row.isKnown = true
        // Defaults from Word.init: interval=0, easeFactor=2.5, nextReviewDate=nil.
        // This represents the state of an isKnown=true row right after a lightweight
        // schema rename adds the new SRS fields with their defaults.
        context.insert(row)
        try context.save()

        let migrationNow = Date(timeIntervalSince1970: 1_800_000_000)
        try CamuseanMigrationPlan.applyV1toV2Mapping(in: context, now: migrationNow)

        let result = try context.fetch(FetchDescriptor<Word>())
        try #require(result.count == 1)
        let migrated = result[0]
        #expect(migrated.word == "bonjour")
        #expect(migrated.isKnown == true) // legacy field retained
        #expect(migrated.interval == 365)
        #expect(abs(migrated.easeFactor - 2.5) < 0.0001)
        let expected = Calendar.current.date(byAdding: .day, value: 365, to: migrationNow)
        #expect(migrated.nextReviewDate == expected)
    }

    // 2. CRITICAL: a row where isKnown=false must keep nextReviewDate=nil so it still
    //    appears in Review (matching v1.0 behavior — it was due, still due).
    @Test func isKnownFalseRowMigratesAsDue() throws {
        let container = try makeV2Container()
        let context = ModelContext(container)

        let row = Word(
            word: "flâner",
            sourceLanguage: "French",
            targetLanguage: "English"
        )
        row.isKnown = false
        context.insert(row)
        try context.save()

        try CamuseanMigrationPlan.applyV1toV2Mapping(in: context, now: Date())

        let result = try context.fetch(FetchDescriptor<Word>())
        try #require(result.count == 1)
        let migrated = result[0]
        #expect(migrated.word == "flâner")
        #expect(migrated.isKnown == false)
        #expect(migrated.interval == 0)
        #expect(abs(migrated.easeFactor - 2.5) < 0.0001)
        #expect(migrated.nextReviewDate == nil)
    }

    // 3. CRITICAL: all non-SRS fields (word, definition, exampleSentence, languages, timestamp)
    //    must be preserved verbatim across the mapping.
    @Test func nonSRSFieldsPreservedVerbatim() throws {
        let container = try makeV2Container()
        let context = ModelContext(container)

        let frozenTimestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let row = Word(
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

        let result = try context.fetch(FetchDescriptor<Word>())
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
