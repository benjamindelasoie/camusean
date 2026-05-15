import Foundation
import SwiftData

@Model
final class Word {
    var word: String
    var definition: String
    var exampleSentence: String
    var sourceLanguage: String
    var targetLanguage: String
    var timestamp: Date
    var isKnown: Bool

    init(
        word: String,
        definition: String = "",
        exampleSentence: String = "",
        sourceLanguage: String,
        targetLanguage: String
    ) {
        self.word = word
        self.definition = definition
        self.exampleSentence = exampleSentence
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.timestamp = Date()
        self.isKnown = false
    }
}
