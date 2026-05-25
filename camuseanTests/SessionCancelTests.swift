import Foundation
import Testing
import SwiftData
@testable import camusean

@MainActor
@Suite struct SessionCancelTests {

    // Build an in-memory container so we can exercise modelContext.delete without driving
    // a real ModelContainer file. Each test gets its own container.
    private func makeContext() -> ModelContext {
        let schema = Schema(versionedSchema: CamuseanSchemaV2.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // 1. Cancel after saveWord: the currentWord is deleted, recentlyRejected gets its
    //    transcription, phase resets to .listening, lookupCancelled flag is set.
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
        vm.phase = .result("bonjour", "hello")

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

        // Verify the Word is actually gone from the context.
        let remaining = try? context.fetch(FetchDescriptor<Word>())
        #expect(remaining?.isEmpty == true)
    }

    // 2. Cancel during .processing (before saveWord): no currentWord exists yet, but the
    //    transcription comes from the phase enum's associated value.
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

    // 3. A second cancel when there's nothing in flight is a no-op (no crash, idempotent).
    @Test func doubleCancelIsIdempotent() {
        let vm = SessionViewModel()
        vm.modelContext = makeContext()
        vm.phase = .processing("hello")

        vm.cancelCurrentLookup()
        let firstCount = vm.recentlyRejected.count

        // Phase is now .listening, currentWord is nil. Second cancel should not crash
        // and should not add another rejection (no transcription to capture).
        vm.cancelCurrentLookup()
        #expect(vm.recentlyRejected.count == firstCount)
    }

    // 4. Cancel when phase is .listening and there's nothing in flight: should be safe.
    //    Doesn't add to recentlyRejected (no transcription available).
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

    // 5. The rejection timestamp is approximately "now" so the entry is treated as in-window
    //    by subsequent filterCandidates calls.
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
