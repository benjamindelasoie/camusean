import Foundation
import Testing
@testable import camusean

// Network-free coverage for the Open Library edition parser + MARC→locale mapping. The canned JSON
// mirrors the exact shapes observed from the live /isbn/{isbn}.json endpoint (fr/en/es editions,
// plus the no-language / no-cover / no-title edges).
@Suite struct OpenLibraryServiceTests {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    // MARK: parseEdition — real shapes

    @Test func parsesFrenchEdition() throws {
        let json = #"""
        {"title":"L’étranger","key":"/books/OL37027182M","by_statement":null,
         "languages":[{"key":"/languages/fre"}],"works":[{"key":"/works/OL1230613W"}],
         "covers":[15166217,15115103]}
        """#
        let b = try OpenLibraryService.parseEdition(from: data(json), isbn: "9782070360024")
        #expect(b.title == "L’étranger")
        #expect(b.locale == "fr-FR")
        #expect(b.coverURL == "https://covers.openlibrary.org/b/id/15166217-M.jpg")
        #expect(b.openLibraryEditionID == "OL37027182M")
        #expect(b.openLibraryWorkID == "OL1230613W")
        #expect(b.author == "")          // by_statement null → blank, editable on the confirm card
        #expect(b.isbn == "9782070360024")
    }

    @Test func parsesEnglishEdition() throws {
        let json = #"""
        {"title":"Nineteen Eighty-Four","key":"/books/OL1234M",
         "languages":[{"key":"/languages/eng"}],"works":[{"key":"/works/OL1168083W"}],
         "covers":[12054527]}
        """#
        let b = try OpenLibraryService.parseEdition(from: data(json), isbn: "9780451524935")
        #expect(b.title == "Nineteen Eighty-Four")
        #expect(b.locale == "en-US")
        #expect(b.coverURL == "https://covers.openlibrary.org/b/id/12054527-M.jpg")
    }

    @Test func parsesSpanishEditionWithAuthor() throws {
        let json = #"""
        {"title":"Cien años de soledad","key":"/books/OL5678M",
         "by_statement":"Gabriel García Márquez ; edición de Jacques Joset.",
         "languages":[{"key":"/languages/spa"}],"works":[{"key":"/works/OL274505W"}],
         "covers":[1047469]}
        """#
        let b = try OpenLibraryService.parseEdition(from: data(json), isbn: "9788437604947")
        #expect(b.locale == "es-ES")
        #expect(b.author == "Gabriel García Márquez ; edición de Jacques Joset.")
    }

    // MARK: edges

    @Test func missingLanguageYieldsNilLocale() throws {
        let json = #"{"title":"Untitled Edition","key":"/books/OL9M","works":[{"key":"/works/OL9W"}]}"#
        let b = try OpenLibraryService.parseEdition(from: data(json), isbn: "1")
        #expect(b.locale == nil)         // → user picks on the confirm card
        #expect(b.coverURL == nil)
    }

    @Test func unknownMARCCodeYieldsNilLocale() throws {
        let json = #"{"title":"Война и мир","languages":[{"key":"/languages/rus"}]}"#
        let b = try OpenLibraryService.parseEdition(from: data(json), isbn: "1")
        #expect(b.locale == nil)         // Russian isn't a supported reading language
    }

    @Test func placeholderCoverIDIsIgnored() throws {
        // OL sometimes emits -1 for "no cover".
        let json = #"{"title":"X","languages":[{"key":"/languages/fre"}],"covers":[-1]}"#
        let b = try OpenLibraryService.parseEdition(from: data(json), isbn: "1")
        #expect(b.coverURL == nil)
    }

    @Test func missingTitleThrowsNotFound() {
        let json = #"{"key":"/books/OL1M","languages":[{"key":"/languages/fre"}]}"#
        #expect(throws: OpenLibraryError.notFound) {
            _ = try OpenLibraryService.parseEdition(from: data(json), isbn: "1")
        }
    }

    @Test func malformedJSONThrowsDecoding() {
        #expect(throws: OpenLibraryError.decoding) {
            _ = try OpenLibraryService.parseEdition(from: data("not json"), isbn: "1")
        }
    }

    // MARK: marcToLocale + normalizedISBN

    @Test func marcToLocaleMapsSupportedCodes() {
        #expect(OpenLibraryService.marcToLocale("fre") == "fr-FR")
        #expect(OpenLibraryService.marcToLocale("fra") == "fr-FR")   // ISO 639-2/T spelling
        #expect(OpenLibraryService.marcToLocale("eng") == "en-US")
        #expect(OpenLibraryService.marcToLocale("spa") == "es-ES")
        #expect(OpenLibraryService.marcToLocale("ita") == "it-IT")
        #expect(OpenLibraryService.marcToLocale("ger") == "de-DE")
        #expect(OpenLibraryService.marcToLocale("deu") == "de-DE")
        #expect(OpenLibraryService.marcToLocale("por") == "pt-PT")
    }

    @Test func marcToLocaleReturnsNilForUnsupported() {
        #expect(OpenLibraryService.marcToLocale("rus") == nil)
        #expect(OpenLibraryService.marcToLocale("jpn") == nil)
        #expect(OpenLibraryService.marcToLocale("") == nil)
    }

    // MARK: cleanedTitle — reduce OL's catalogue title to the everyday main title

    @Test func cleanedTitleStripsCommaSubtitle() {
        #expect(OpenLibraryService.cleanedTitle("Le mythe de Sisyphe, essai sur l'absurde") == "Le mythe de Sisyphe")
    }

    @Test func cleanedTitleStripsColonSubtitle() {
        #expect(OpenLibraryService.cleanedTitle("Crime and Punishment: A Novel") == "Crime and Punishment")
    }

    @Test func cleanedTitleStripsSeriesParenthetical() {
        #expect(OpenLibraryService.cleanedTitle("Nineteen Eighty-Four (Signet Classics)") == "Nineteen Eighty-Four")
    }

    @Test func cleanedTitleStripsDashSubtitle() {
        #expect(OpenLibraryService.cleanedTitle("Madame Bovary - Mœurs de province") == "Madame Bovary")
    }

    @Test func cleanedTitleLeavesPlainTitleUntouched() {
        #expect(OpenLibraryService.cleanedTitle("L'Étranger") == "L'Étranger")
        #expect(OpenLibraryService.cleanedTitle("Cien años de soledad") == "Cien años de soledad")
        // A hyphen inside a word (no surrounding spaces) is not a subtitle separator.
        #expect(OpenLibraryService.cleanedTitle("Nineteen Eighty-Four") == "Nineteen Eighty-Four")
    }

    @Test func cleanedTitleNeverReturnsEmpty() {
        // Pathological "all subtitle" → fall back to the original rather than empty.
        #expect(OpenLibraryService.cleanedTitle(": only subtitle") == ": only subtitle")
    }

    @Test func normalizedISBNStripsNonDigits() {
        #expect(OpenLibraryService.normalizedISBN("978-2-07-036002-4") == "9782070360024")
        #expect(OpenLibraryService.normalizedISBN("  0451524934 ") == "0451524934")
        #expect(OpenLibraryService.normalizedISBN("080442957x") == "080442957X")  // ISBN-10 check digit
    }
}
