import Testing
@testable import camusean

@Suite("VoiceSetup.relevantLanguages")
struct VoiceSetupTests {

    @Test("a non-English reading language pairs with English")
    func frenchPairsWithEnglish() {
        let langs = VoiceSetup.relevantLanguages(readingLocale: "fr-FR")
        #expect(langs.map(\.name) == ["French", "English"])
    }

    @Test("English reading language does not duplicate English")
    func englishDoesNotDuplicate() {
        let langs = VoiceSetup.relevantLanguages(readingLocale: "en-US")
        #expect(langs.map(\.name) == ["English"])
    }

    @Test("Spanish reading language pairs with English")
    func spanishPairsWithEnglish() {
        let langs = VoiceSetup.relevantLanguages(readingLocale: "es-ES")
        #expect(langs.map(\.locale) == ["es-ES", "en-US"])
    }

    @Test("an unknown locale falls back to French, still paired with English")
    func unknownLocaleFallsBackToFrench() {
        let langs = VoiceSetup.relevantLanguages(readingLocale: "xx-XX")
        #expect(langs.map(\.name) == ["French", "English"])
    }

    @Test("named() resolves a known locale and falls back for unknown")
    func namedResolvesAndFallsBack() {
        #expect(ReadingLanguage.named(locale: "en-US").name == "English")
        #expect(ReadingLanguage.named(locale: "de-DE").name == "German")
        #expect(ReadingLanguage.named(locale: "zz-ZZ").name == "French")
    }

    @Test("English is in the catalog as a reading option")
    func englishIsSelectable() {
        #expect(ReadingLanguage.all.contains { $0.locale == "en-US" })
    }
}
