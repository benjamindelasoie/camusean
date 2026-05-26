import Foundation

// Catalog of languages the user can read in. The target/definition language is always
// English (see SessionViewModel.targetName), so English appears here only as a *reading*
// option — choosing it gives monolingual English definitions for hard words.
struct ReadingLanguage: Identifiable, Hashable {
    let name: String
    let locale: String      // BCP-47 identifier for SFSpeechRecognizer + TTS, e.g. "fr-FR"
    let flag: String

    var id: String { locale }
    var prefix: String { String(locale.prefix(2)) }   // 2-letter prefix used for voice matching

    static let all: [ReadingLanguage] = [
        ReadingLanguage(name: "French",     locale: "fr-FR", flag: "🇫🇷"),
        ReadingLanguage(name: "English",    locale: "en-US", flag: "🇬🇧"),
        ReadingLanguage(name: "Spanish",    locale: "es-ES", flag: "🇪🇸"),
        ReadingLanguage(name: "Italian",    locale: "it-IT", flag: "🇮🇹"),
        ReadingLanguage(name: "German",     locale: "de-DE", flag: "🇩🇪"),
        ReadingLanguage(name: "Portuguese", locale: "pt-PT", flag: "🇵🇹"),
    ]

    // The definition language. Definitions always come back in English today.
    // Safe: "en-US" is a literal member of `all` above.
    static let english = all.first { $0.locale == "en-US" }!

    // Catalog entry for a locale; falls back to the first entry (French) for unknown values.
    static func named(locale: String) -> ReadingLanguage {
        all.first { $0.locale == locale } ?? all[0]
    }
}

// Which languages' audio quality matters right now, and whether good voices are installed.
enum VoiceSetup {
    // Pure form: reading language + English (definitions), deduped. Injectable for tests.
    static func relevantLanguages(readingLocale: String) -> [ReadingLanguage] {
        let reading = ReadingLanguage.named(locale: readingLocale)
        return reading.locale == ReadingLanguage.english.locale
            ? [reading]
            : [reading, .english]
    }

    // The languages the app actually speaks, based on the current Settings selection.
    static func relevantLanguages() -> [ReadingLanguage] {
        let locale = UserDefaults.standard.string(forKey: "sourceLanguageLocale") ?? "fr-FR"
        return relevantLanguages(readingLocale: locale)
    }

    // True if any relevant language lacks an Enhanced/Premium voice (so the app sounds robotic).
    @MainActor
    static func isAnyVoiceMissing() -> Bool {
        relevantLanguages().contains { !TTSService.hasEnhancedVoice(forLanguagePrefix: $0.prefix) }
    }
}
