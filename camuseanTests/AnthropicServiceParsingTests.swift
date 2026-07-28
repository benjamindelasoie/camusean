import Foundation
import Testing
@testable import camusean

// Pure-parsing coverage for the misfire-correction lookup contract. No network, no actor —
// `parseLookupResult` / `normalizeCorrection` are nonisolated statics by design so the JSON
// contract (correctedWord normalization, markdown fences, malformed input) is unit-testable.
@Suite struct AnthropicServiceParsingTests {

    // MARK: parseLookupResult

    @Test func parsesDefinitionExampleAndCorrection() throws {
        let json = #"{"correctedWord": "flâner", "definition": "to stroll", "exampleSentence": "J'aime flâner."}"#
        let r = try AnthropicService.parseLookupResult(from: json, original: "flaner")
        #expect(r.definition == "to stroll")
        #expect(r.exampleSentence == "J'aime flâner.")
        #expect(r.correctedWord == "flâner")
    }

    @Test func correctionIdenticalToOriginalCollapsesToNil() throws {
        // Claude kept the word (already valid) — not a correction.
        let json = #"{"correctedWord": "bonjour", "definition": "hello", "exampleSentence": "Bonjour!"}"#
        let r = try AnthropicService.parseLookupResult(from: json, original: "bonjour")
        #expect(r.correctedWord == nil)
    }

    @Test func correctionMatchingOriginalCaseInsensitivelyCollapsesToNil() throws {
        let json = #"{"correctedWord": "Bonjour", "definition": "hello", "exampleSentence": "Bonjour!"}"#
        let r = try AnthropicService.parseLookupResult(from: json, original: "bonjour")
        #expect(r.correctedWord == nil)
    }

    @Test func blankCorrectionCollapsesToNil() throws {
        let json = #"{"correctedWord": "   ", "definition": "hello", "exampleSentence": "Bonjour!"}"#
        let r = try AnthropicService.parseLookupResult(from: json, original: "bonjour")
        #expect(r.correctedWord == nil)
    }

    @Test func absentCorrectionFieldDecodesToNil() throws {
        // Backwards-compatible: a reply without correctedWord still parses.
        let json = #"{"definition": "hello", "exampleSentence": "Bonjour!"}"#
        let r = try AnthropicService.parseLookupResult(from: json, original: "bonjour")
        #expect(r.correctedWord == nil)
        #expect(r.definition == "hello")
    }

    @Test func stripsMarkdownFencesBeforeDecoding() throws {
        let fenced = """
        ```json
        {"correctedWord": "livre", "definition": "book", "exampleSentence": "Un livre."}
        ```
        """
        let r = try AnthropicService.parseLookupResult(from: fenced, original: "leevr")
        #expect(r.correctedWord == "livre")
        #expect(r.definition == "book")
    }

    @Test func extractsObjectFromSurroundingProse() throws {
        // extractJSON takes first { ... last }, so stray prose around the object is tolerated.
        let noisy = #"Here you go: {"correctedWord": "merci", "definition": "thank you", "exampleSentence": "Merci!"} hope that helps"#
        let r = try AnthropicService.parseLookupResult(from: noisy, original: "mercy")
        #expect(r.correctedWord == "merci")
    }

    @Test func malformedJSONThrowsMalformedResponse() {
        let garbage = "not json at all"
        #expect(throws: LookupError.self) {
            _ = try AnthropicService.parseLookupResult(from: garbage, original: "x")
        }
    }

    @Test func missingRequiredFieldThrows() {
        // No definition key — decode fails.
        let json = #"{"correctedWord": "livre", "exampleSentence": "Un livre."}"#
        #expect(throws: LookupError.self) {
            _ = try AnthropicService.parseLookupResult(from: json, original: "leevr")
        }
    }

    // MARK: formNote

    @Test func parsesFormNoteWhenPresent() throws {
        let json = #"{"correctedWord": "disparu", "definition": "gone or vanished", "formNote": "Past participle of disparaître", "exampleSentence": "Il a disparu."}"#
        let r = try AnthropicService.parseLookupResult(from: json, original: "disparu")
        #expect(r.formNote == "Past participle of disparaître")
    }

    @Test func absentFormNoteFieldDecodesToNil() throws {
        // A plain dictionary-form word teaches nothing extra, and older replies omit the key.
        let json = #"{"correctedWord": "livre", "definition": "book", "exampleSentence": "Un livre."}"#
        let r = try AnthropicService.parseLookupResult(from: json, original: "livre")
        #expect(r.formNote == nil)
    }

    @Test func jsonNullFormNoteDecodesToNil() throws {
        let json = #"{"definition": "book", "formNote": null, "exampleSentence": "Un livre."}"#
        let r = try AnthropicService.parseLookupResult(from: json, original: "livre")
        #expect(r.formNote == nil)
    }

    @Test func blankFormNoteCollapsesToNil() throws {
        let json = #"{"definition": "book", "formNote": "   ", "exampleSentence": "Un livre."}"#
        let r = try AnthropicService.parseLookupResult(from: json, original: "livre")
        #expect(r.formNote == nil)
    }

    @Test func stringNullFormNoteCollapsesToNil() throws {
        // Models sometimes emit the word "null" *inside* the string rather than a JSON null.
        // Without this the reader would see a literal "null" under the definition.
        let json = #"{"definition": "book", "formNote": "null", "exampleSentence": "Un livre."}"#
        let r = try AnthropicService.parseLookupResult(from: json, original: "livre")
        #expect(r.formNote == nil)
    }

    // MARK: normalizeFormNote

    @Test func normalizeFormNoteTrimsAndKeepsText() {
        #expect(AnthropicService.normalizeFormNote("  Feminine of fatigué  ") == "Feminine of fatigué")
    }

    @Test func normalizeFormNoteReturnsNilForEmptyish() {
        #expect(AnthropicService.normalizeFormNote(nil) == nil)
        #expect(AnthropicService.normalizeFormNote("") == nil)
        #expect(AnthropicService.normalizeFormNote("   ") == nil)
        #expect(AnthropicService.normalizeFormNote("null") == nil)
        #expect(AnthropicService.normalizeFormNote("NULL") == nil)
        #expect(AnthropicService.normalizeFormNote(" Null ") == nil)
    }

    // MARK: normalizeCorrection

    @Test func normalizeKeepsDistinctTrimmedWord() {
        #expect(AnthropicService.normalizeCorrection("  flâner  ", original: "flaner") == "flâner")
    }

    @Test func normalizeReturnsNilForNilBlankOrSame() {
        #expect(AnthropicService.normalizeCorrection(nil, original: "x") == nil)
        #expect(AnthropicService.normalizeCorrection("", original: "x") == nil)
        #expect(AnthropicService.normalizeCorrection("  ", original: "x") == nil)
        #expect(AnthropicService.normalizeCorrection("x", original: "x") == nil)
        #expect(AnthropicService.normalizeCorrection("X", original: "x") == nil)
    }
}
