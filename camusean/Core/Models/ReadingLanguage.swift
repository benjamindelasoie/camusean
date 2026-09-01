import Foundation

// Catalog of languages the user can read in. The definition/target language is always English
// (see SessionViewModel.targetName), so English appears here only as a *reading* option.
// `nonisolated` so the immutable catalog stays usable from nonisolated parsing code as well as UI.
nonisolated struct ReadingLanguage: Identifiable, Hashable {
    let name: String
    let locale: String      // BCP-47, e.g. "fr-FR"
    let flag: String

    var id: String { locale }
    var prefix: String { String(locale.prefix(2)) }   // used for voice matching

    static let all: [ReadingLanguage] = [
        ReadingLanguage(name: "French",     locale: "fr-FR", flag: "🇫🇷"),
        ReadingLanguage(name: "English",    locale: "en-US", flag: "🇬🇧"),
        ReadingLanguage(name: "Spanish",    locale: "es-ES", flag: "🇪🇸"),
        ReadingLanguage(name: "Italian",    locale: "it-IT", flag: "🇮🇹"),
        ReadingLanguage(name: "German",     locale: "de-DE", flag: "🇩🇪"),
        ReadingLanguage(name: "Portuguese", locale: "pt-PT", flag: "🇵🇹"),
    ]

    // Force-unwrap safe: "en-US" is a literal member of `all` above.
    static let english = all.first { $0.locale == "en-US" }!

    // Falls back to the first entry (French) for unknown values.
    static func named(locale: String) -> ReadingLanguage {
        all.first { $0.locale == locale } ?? all[0]
    }

    /// Resolves a stored value to a BCP-47 locale, accepting either a display name or a locale.
    ///
    /// `Word.sourceLanguage` persists a DISPLAY NAME ("French"), not a locale, so handing it
    /// straight to a locale-shaped API would silently fall back to the device default. Unknown
    /// values fall back to the reader's current language (not French) so a word saved before a
    /// language switch is not read aloud in the wrong accent.
    static func locale(forName name: String) -> String {
        if let byLocale = all.first(where: { $0.locale == name }) { return byLocale.locale }
        if let byName = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return byName.locale
        }
        return UserDefaults.standard.string(forKey: "sourceLanguageLocale") ?? all[0].locale
    }
}

enum VoiceSetup {
    // Reading language + English (definitions), deduped.
    static func relevantLanguages(readingLocale: String) -> [ReadingLanguage] {
        let reading = ReadingLanguage.named(locale: readingLocale)
        return reading.locale == ReadingLanguage.english.locale
            ? [reading]
            : [reading, .english]
    }

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
