import Foundation
import Testing
@testable import camusean

@Suite struct SpeechServiceCandidatesTests {

    @Test func dedupesCaseInsensitively() {
        let input = ["Bonjour", "bonjour", "BONJOUR"]
        let result = SpeechRecognition.extractDistinctTranscriptions(from: input)
        #expect(result == ["Bonjour"])
    }

    @Test func capsAtMaxEntries() {
        let input = ["one", "two", "three", "four", "five"]
        let result = SpeechRecognition.extractDistinctTranscriptions(from: input, max: 3)
        #expect(result.count == 3)
        #expect(result == ["one", "two", "three"])
    }

    @Test func emptyInputReturnsEmpty() {
        let result = SpeechRecognition.extractDistinctTranscriptions(from: [])
        #expect(result.isEmpty)
    }

    // Order is preserved because Apple returns candidates in confidence order.
    @Test func preservesOriginalOrder() {
        let input = ["alpha", "bravo", "charlie"]
        let result = SpeechRecognition.extractDistinctTranscriptions(from: input)
        #expect(result == ["alpha", "bravo", "charlie"])
    }

    @Test func trimsWhitespaceAndDropsEmpty() {
        let input = ["  hello  ", "world", "   ", "hello"]
        let result = SpeechRecognition.extractDistinctTranscriptions(from: input)
        #expect(result == ["hello", "world"])
    }
}
