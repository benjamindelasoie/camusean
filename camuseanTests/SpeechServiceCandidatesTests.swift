import Foundation
import Testing
@testable import camusean

@Suite struct SpeechServiceCandidatesTests {

    // 1. Case-insensitive dedup. "Bonjour", "bonjour", "BONJOUR" should collapse to one entry,
    //    keeping the first occurrence's original casing.
    @Test func dedupesCaseInsensitively() {
        let input = ["Bonjour", "bonjour", "BONJOUR"]
        let result = SpeechService.extractDistinctTranscriptions(from: input)
        #expect(result == ["Bonjour"])
    }

    // 2. Caps at `max` entries. With max=3 and 5 distinct strings, returns the first 3.
    @Test func capsAtMaxEntries() {
        let input = ["one", "two", "three", "four", "five"]
        let result = SpeechService.extractDistinctTranscriptions(from: input, max: 3)
        #expect(result.count == 3)
        #expect(result == ["one", "two", "three"])
    }

    // 3. Empty input returns empty output. No crashes on edge.
    @Test func emptyInputReturnsEmpty() {
        let result = SpeechService.extractDistinctTranscriptions(from: [])
        #expect(result.isEmpty)
    }

    // 4. Order is preserved from the input (Apple returns candidates in confidence order).
    @Test func preservesOriginalOrder() {
        let input = ["alpha", "bravo", "charlie"]
        let result = SpeechService.extractDistinctTranscriptions(from: input)
        #expect(result == ["alpha", "bravo", "charlie"])
    }

    // 5. Whitespace is trimmed before dedup. Entries that become empty after trim are dropped.
    @Test func trimsWhitespaceAndDropsEmpty() {
        let input = ["  hello  ", "world", "   ", "hello"]
        let result = SpeechService.extractDistinctTranscriptions(from: input)
        #expect(result == ["hello", "world"])
    }
}
