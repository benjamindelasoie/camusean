import Foundation
import Testing
import SwiftData
import Dependencies
@testable import camusean

// Exercises the retrieval flow end-to-end without hardware: the Anthropic network call, the
// Keychain read, and speech output are overridden through their swift-dependencies seams. Before
// those seams the flow hit the real AVSpeechSynthesizer, whose delegate never fires in a unit
// test, hanging it. Driven through `debugSimulateHeardWord`, the DEBUG hook that feeds a word
// into `lookup(word:)` as if the mic had heard it.
@MainActor
@Suite struct SessionLookupTests {

    private func makeContext() -> ModelContext {
        let schema = Schema(versionedSchema: CamuseanSchemaV4.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func stubLookup(_ result: LookupResult) -> WordLookupClient {
        WordLookupClient(lookup: { _, _, _, _, _, _ in result })
    }

    private func savedWords(_ context: ModelContext) -> [Word] {
        (try? context.fetch(FetchDescriptor<Word>())) ?? []
    }

    @Test func successfulLookupSavesWordAndAdvances() async {
        let context = makeContext()
        let result = LookupResult(definition: "hello", exampleSentence: "Bonjour!", correctedWord: nil, formNote: nil)

        await withDependencies {
            $0.wordLookup = stubLookup(result)
            $0.apiKeyStore = APIKeyStore(load: { "sk-ant-test" }, save: { _ in })
            $0.speechSynthesizer = .testValue
        } operation: {
            let vm = SessionViewModel()
            vm.modelContext = context
            await vm.debugSimulateHeardWord("bonjour")

            #expect(vm.lookupCount == 1)
            let words = savedWords(context)
            #expect(words.count == 1)
            #expect(words.first?.word == "bonjour")
            #expect(words.first?.definition == "hello")
            if case .result(let w, let def, _) = vm.phase {
                #expect(w == "bonjour")
                #expect(def == "hello")
            } else {
                Issue.record("expected .result, got \(vm.phase)")
            }
        }
    }

    @Test func correctionRewritesSavedWord() async {
        UserDefaults.standard.set(true, forKey: "wordCorrectionEnabled")
        let context = makeContext()
        let result = LookupResult(definition: "to stroll", exampleSentence: "Je flâne.", correctedWord: "flâner", formNote: nil)

        await withDependencies {
            $0.wordLookup = stubLookup(result)
            $0.apiKeyStore = APIKeyStore(load: { "sk-ant-test" }, save: { _ in })
            $0.speechSynthesizer = .testValue
        } operation: {
            let vm = SessionViewModel()
            vm.modelContext = context
            await vm.debugSimulateHeardWord("flaner")

            let words = savedWords(context)
            #expect(words.count == 1)
            #expect(words.first?.word == "flâner")
        }
    }

    @Test func missingKeySavesWordWithEmptyDefinitionAndErrors() async {
        let context = makeContext()

        await withDependencies {
            $0.wordLookup = WordLookupClient(lookup: { _, _, _, _, _, _ in
                Issue.record("lookup must not run without an API key")
                throw LookupError.invalidResponse
            })
            $0.apiKeyStore = APIKeyStore(load: { nil }, save: { _ in })
            $0.speechSynthesizer = .testValue
        } operation: {
            let vm = SessionViewModel()
            vm.modelContext = context
            await vm.debugSimulateHeardWord("bonjour")

            #expect(vm.lookupCount == 0)
            let words = savedWords(context)
            #expect(words.count == 1)
            #expect(words.first?.definition.isEmpty == true)
            if case .error = vm.phase {} else {
                Issue.record("expected .error, got \(vm.phase)")
            }
        }
    }

    @Test func lookupFailureSavesWordAndSurfacesFriendlyError() async {
        let context = makeContext()

        await withDependencies {
            $0.wordLookup = WordLookupClient(lookup: { _, _, _, _, _, _ in
                throw URLError(.notConnectedToInternet)
            })
            $0.apiKeyStore = APIKeyStore(load: { "sk-ant-test" }, save: { _ in })
            $0.speechSynthesizer = .testValue
        } operation: {
            let vm = SessionViewModel()
            vm.modelContext = context
            await vm.debugSimulateHeardWord("bonjour")

            #expect(vm.lookupCount == 0)
            let words = savedWords(context)
            #expect(words.count == 1)
            #expect(words.first?.definition.isEmpty == true)
            if case .error = vm.phase {} else {
                Issue.record("expected .error, got \(vm.phase)")
            }
        }
    }
}
