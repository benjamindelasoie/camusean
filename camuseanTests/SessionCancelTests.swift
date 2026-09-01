import Foundation
import Testing
import SwiftData
@testable import camusean

@MainActor
@Suite struct SessionCancelTests {

    private func makeContext() -> ModelContext {
        // Must match the version the `Word` typealias points at — inserting a current-version
        // model into an older-version container traps inside SwiftData.
        let schema = Schema(versionedSchema: CamuseanSchemaV4.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func cancelDeletesCurrentWordAndRecordsRejection() {
        let vm = SessionViewModel()
        let context = makeContext()
        vm.modelContext = context

        let word = Word(
            word: "bonjour",
            sourceLanguage: "French",
            targetLanguage: "English"
        )
        context.insert(word)
        try? context.save()
        vm.currentWord = word
        vm.phase = .result("bonjour", "hello", nil)

        vm.cancelCurrentLookup()

        #expect(vm.currentWord == nil)
        #expect(vm.lookupCancelled == true)
        #expect(vm.recentlyRejected.count == 1)
        #expect(vm.recentlyRejected.first?.transcription == "bonjour")
        if case .listening = vm.phase {
            // expected
        } else {
            Issue.record("phase should be .listening after cancel, got \(vm.phase)")
        }

        let remaining = try? context.fetch(FetchDescriptor<Word>())
        #expect(remaining?.isEmpty == true)
    }

    @Test func cancelDuringProcessingCapturesFromPhase() {
        let vm = SessionViewModel()
        vm.modelContext = makeContext()

        vm.phase = .processing("flâner")
        // currentWord intentionally nil — simulates cancel before saveWord ran.

        vm.cancelCurrentLookup()

        #expect(vm.lookupCancelled == true)
        #expect(vm.recentlyRejected.count == 1)
        #expect(vm.recentlyRejected.first?.transcription == "flâner")
        if case .listening = vm.phase {
            // expected
        } else {
            Issue.record("phase should be .listening after cancel, got \(vm.phase)")
        }
    }

    @Test func doubleCancelIsIdempotent() {
        let vm = SessionViewModel()
        vm.modelContext = makeContext()
        vm.phase = .processing("hello")

        vm.cancelCurrentLookup()
        let firstCount = vm.recentlyRejected.count

        // Second cancel has no transcription to capture, so it must not add a rejection.
        vm.cancelCurrentLookup()
        #expect(vm.recentlyRejected.count == firstCount)
    }

    @Test func cancelDuringListeningIsHarmless() {
        let vm = SessionViewModel()
        vm.modelContext = makeContext()
        vm.phase = .listening

        vm.cancelCurrentLookup()

        #expect(vm.recentlyRejected.isEmpty)
        if case .listening = vm.phase {
            // expected
        } else {
            Issue.record("phase should remain .listening, got \(vm.phase)")
        }
    }

    // The timestamp must be "now" so the entry stays in-window for later filterCandidates calls.
    @Test func cancelRecordsCurrentTimestamp() throws {
        let vm = SessionViewModel()
        vm.modelContext = makeContext()
        vm.phase = .processing("test")

        let before = Date()
        vm.cancelCurrentLookup()
        let after = Date()

        let rejectedAt = try #require(vm.recentlyRejected.first?.at)
        #expect(rejectedAt >= before)
        #expect(rejectedAt <= after)
    }
}
