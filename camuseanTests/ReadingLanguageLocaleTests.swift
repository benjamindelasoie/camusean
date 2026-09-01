import Testing
import Foundation
@testable import camusean

// Regression guard: `Word.sourceLanguage` persists a DISPLAY NAME ("French"), not a locale.
// Handing that to `TTSService.speak(language:)` matched no voice (`bestVoice` compares the first
// two characters, and "Fr" never matches "fr-FR"), so a French word got read aloud in an English
// voice.
@Suite("Reading language locale resolution")
struct ReadingLanguageLocaleTests {

    @Test func resolvesDisplayNamesToLocales() {
        #expect(ReadingLanguage.locale(forName: "French") == "fr-FR")
        #expect(ReadingLanguage.locale(forName: "Spanish") == "es-ES")
        #expect(ReadingLanguage.locale(forName: "German") == "de-DE")
    }

    @Test func acceptsLocalesUnchanged() {
        // Callers should not have to know which form they are holding.
        #expect(ReadingLanguage.locale(forName: "fr-FR") == "fr-FR")
        #expect(ReadingLanguage.locale(forName: "pt-PT") == "pt-PT")
    }

    @Test func nameMatchingIgnoresCase() {
        #expect(ReadingLanguage.locale(forName: "french") == "fr-FR")
        #expect(ReadingLanguage.locale(forName: "FRENCH") == "fr-FR")
    }

    @Test func everyCatalogNameResolvesToItsOwnLocale() {
        for language in ReadingLanguage.all {
            #expect(ReadingLanguage.locale(forName: language.name) == language.locale)
        }
    }

    @Test func resolvedLocalesAreVoiceMatchable() {
        // The actual failure mode: the value has to survive bestVoice's prefix comparison,
        // which is case-sensitive. A display name does not.
        for language in ReadingLanguage.all {
            let resolved = ReadingLanguage.locale(forName: language.name)
            #expect(resolved.prefix(2) == resolved.prefix(2).lowercased())
            #expect(resolved.contains("-"))
        }
        #expect(ReadingLanguage.locale(forName: "French").prefix(2) != "Fr")
    }

    @Test func unknownValueFallsBackToTheCurrentReadingLocale() {
        // A word saved before a language switch should not be read in the wrong accent.
        let previous = UserDefaults.standard.string(forKey: "sourceLanguageLocale")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "sourceLanguageLocale") }
            else { UserDefaults.standard.removeObject(forKey: "sourceLanguageLocale") }
        }
        UserDefaults.standard.set("it-IT", forKey: "sourceLanguageLocale")
        #expect(ReadingLanguage.locale(forName: "Klingon") == "it-IT")
    }
}
