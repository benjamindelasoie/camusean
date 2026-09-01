import Dependencies
import Foundation

struct LookupResult: Sendable {
    /// Target-language only and safe to speak — the prompt forbids source-language text (see `formNote`).
    let definition: String
    let exampleSentence: String
    /// The word Claude thinks was intended when the transcription was a mishearing; nil = kept as-is.
    let correctedWord: String?
    /// Morphology note for an inflected form ("Past participle of disparaître"). DISPLAYED, NEVER
    /// SPOKEN — it contains source-language words the TTS voice would mangle. nil = dictionary form.
    let formNote: String?
}

// Decodable reply shape. Optional fields so older responses still decode; both are normalized by
// `parseLookupResult`. `nonisolated` so decoding works off the main actor.
private nonisolated struct LookupJSON: Decodable {
    let definition: String
    let exampleSentence: String
    let correctedWord: String?
    let formNote: String?
}

actor AnthropicService {
    private let model = "claude-haiku-4-5-20251001"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let dailyCap = 200
    private var dailyCount = 0
    private var lastResetDate = Calendar.current.startOfDay(for: Date())

    func lookup(
        word: String,
        sourceLanguage: String,
        targetLanguage: String,
        bookContext: String? = nil,
        recentlyRejected: [String] = [],
        apiKey: String
    ) async throws -> LookupResult {
        resetDailyCountIfNeeded()
        guard dailyCount < dailyCap else { throw LookupError.dailyCapReached }

        // Negative context: bias Claude away from re-deriving a repeated mishearing. Strip
        // quotes/newlines so a stray transcription character can't malform the prompt.
        let sanitizedRejections = recentlyRejected
            .map { $0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let rejectedClause = sanitizedRejections.isEmpty ? "" : "\n- Never choose any of these already-rejected words: " +
            sanitizedRejections.map { "\"\($0)\"" }.joined(separator: ", ") + "."

        // Book context disambiguates the word's *sense* only — it must never swap a valid word for
        // a thematically-related one (the "suicide" → "Sisyphe" failure), so it's applied only when
        // defining, after the word is decided.
        let bookClause: String = {
            guard let raw = bookContext?.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return "" }
            return " The reader is reading \"\(raw)\"; use that ONLY to pick the most fitting sense — never to change which word is defined."
        }()

        // The transcription is a hypothesis, not ground truth (one candidate on iOS 26, non-native
        // reader), so Claude corrects the word before defining it — same call. The keep-if-valid
        // guard is strict: corrections follow sound, never the book's topic. A short phrase is allowed.
        let prompt = """
        Someone reading aloud in \(sourceLanguage) (not a native \(sourceLanguage) speaker) spoke a word or short phrase that on-device speech recognition transcribed as "\(word)". The transcription may be phonetically inaccurate.

        Decide the most likely intended \(sourceLanguage) word or expression:
        - If "\(word)" is already a valid \(sourceLanguage) word or expression, keep it EXACTLY — even if a different word would fit the book's theme better. Only change it to fix a clear phonetic mishearing.
        - Otherwise infer the most likely intended \(sourceLanguage) word or expression that SOUNDS like the transcription — not merely one related to the book.
        - NEVER change the grammatical form. Preserve the exact gender, number, and tense that was said, even when another form sounds identical. The reader wants the form they actually met on the page, not its dictionary form. Correct sound, never grammar.\(rejectedClause)

        Then define it in \(targetLanguage).\(bookClause)

        The definition is spoken aloud by a \(targetLanguage) text-to-speech voice, so:
        - Write it ONLY in \(targetLanguage). It must contain no \(sourceLanguage) words at all — not even the word being defined, which the app already pronounces separately in a native voice. A \(targetLanguage) voice mangles \(sourceLanguage) words.
        - Keep it short and natural to hear.

        If the word is an inflected form, put the grammar lesson in "formNote" instead. That field is displayed on screen and never spoken, so it MAY contain \(sourceLanguage) words — give the form and its dictionary form, e.g. "Past participle of <infinitive>", "Feminine singular of <base adjective>", "Plural of <singular noun>". Use null when the word is already its dictionary form and there is nothing extra to teach.

        Reply with ONLY a JSON object, no markdown, no extra text. Replace each angle-bracket placeholder with a real value:
        {"correctedWord": "<the intended \(sourceLanguage) word or expression>", "definition": "<short \(targetLanguage)-only definition>", "formNote": "<grammar note, or null>", "exampleSentence": "<example sentence>"}
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": model,
            // A ceiling, not a target — a truncated reply is unparseable JSON, i.e. a failed lookup.
            "max_tokens": 384,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw LookupError.invalidResponse }

        let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
        print("[Anthropic] status=\(http.statusCode) body=\(rawBody)")

        switch http.statusCode {
        case 200: break
        case 401: throw LookupError.unauthorized
        case 429: throw LookupError.rateLimited
        default: throw LookupError.serverError(http.statusCode, rawBody)
        }

        guard
            let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = (outer["content"] as? [[String: Any]])?.first,
            let text = content["text"] as? String
        else { throw LookupError.malformedResponse("couldn't parse API envelope") }

        print("[Anthropic] model text: \(text)")

        let result = try Self.parseLookupResult(from: text, original: word)
        dailyCount += 1
        return result
    }

    // `nonisolated static` so it's unit-testable without a network round-trip.
    nonisolated static func parseLookupResult(from text: String, original: String) throws -> LookupResult {
        let extracted = extractJSON(from: text)
        guard let jsonData = extracted.data(using: .utf8) else {
            throw LookupError.malformedResponse("non-utf8 response: \(extracted)")
        }
        let decoded: LookupJSON
        do {
            decoded = try JSONDecoder().decode(LookupJSON.self, from: jsonData)
        } catch {
            throw LookupError.malformedResponse("couldn't decode JSON: \(extracted)")
        }
        return LookupResult(
            definition: decoded.definition,
            exampleSentence: decoded.exampleSentence,
            correctedWord: normalizeCorrection(decoded.correctedWord, original: original),
            formNote: normalizeFormNote(decoded.formNote)
        )
    }

    // Blank, whitespace, or the literal string "null" (models sometimes emit that inside the JSON
    // string) all collapse to nil so the UI shows nothing rather than an empty line.
    nonisolated static func normalizeFormNote(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "null" else { return nil }
        return trimmed
    }

    // A correction only counts when it's non-blank AND actually differs from the transcription.
    nonisolated static func normalizeCorrection(_ raw: String?, original: String) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let originalTrimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare(originalTrimmed) == .orderedSame { return nil }
        return trimmed
    }

    nonisolated static func extractJSON(from text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") {
            return String(s[start...end])
        }
        return s
    }

    private func resetDailyCountIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if today > lastResetDate {
            dailyCount = 0
            lastResetDate = today
        }
    }
}

// swift-dependencies seam (closure-client idiom, off-main-actor). The live client owns one
// `AnthropicService` actor, so the daily cap is a single app-wide counter. testValue throws.
struct WordLookupClient: Sendable {
    var lookup: @Sendable (
        _ word: String,
        _ sourceLanguage: String,
        _ targetLanguage: String,
        _ bookContext: String?,
        _ recentlyRejected: [String],
        _ apiKey: String
    ) async throws -> LookupResult
}

extension WordLookupClient: DependencyKey {
    nonisolated static let liveValue: WordLookupClient = {
        let service = AnthropicService()
        return WordLookupClient(lookup: { word, source, target, bookContext, rejected, apiKey in
            try await service.lookup(
                word: word,
                sourceLanguage: source,
                targetLanguage: target,
                bookContext: bookContext,
                recentlyRejected: rejected,
                apiKey: apiKey
            )
        })
    }()
    nonisolated static let testValue = WordLookupClient(lookup: { _, _, _, _, _, _ in
        throw LookupError.invalidResponse
    })
    nonisolated static var previewValue: WordLookupClient { testValue }
}

extension DependencyValues {
    nonisolated var wordLookup: WordLookupClient {
        get { self[WordLookupClient.self] }
        set { self[WordLookupClient.self] = newValue }
    }
}

enum LookupError: LocalizedError {
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int, String)
    case malformedResponse(String)
    case dailyCapReached

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .unauthorized: "Invalid API key — check Settings"
        case .rateLimited: "Rate limit reached, try again later"
        case .serverError(let code, _): "Server error (\(code))"
        case .malformedResponse: "Couldn't parse definition"
        case .dailyCapReached: "Daily lookup limit reached"
        }
    }
}
