import Foundation

struct LookupResult {
    let definition: String
    let exampleSentence: String
    /// The word Claude believes the reader actually intended, when the speech transcription
    /// was likely a mishearing. `nil` means "no correction" — the transcription was kept as-is
    /// (either already a valid word, or the model returned the same/blank value).
    let correctedWord: String?
}

// Decodable shape of the model's JSON reply. `correctedWord` is optional so older/edge
// responses that omit it still decode; it is normalized to `LookupResult.correctedWord` by
// `AnthropicService.parseLookupResult`.
// `nonisolated` so its synthesized `Decodable` conformance is usable from the nonisolated
// `parseLookupResult` (the module defaults types to @MainActor, which would isolate the
// conformance and break decoding off the main actor).
private nonisolated struct LookupJSON: Decodable {
    let definition: String
    let exampleSentence: String
    let correctedWord: String?
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

        // Negative context: words the reader already rejected this session. Biases Claude away
        // from re-deriving the same wrong interpretation of a repeated mishearing. Strip quotes
        // and newlines first so a stray transcription character can't malform the prompt.
        let sanitizedRejections = recentlyRejected
            .map { $0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let rejectedClause = sanitizedRejections.isEmpty ? "" : "\n- Never choose any of these already-rejected words: " +
            sanitizedRejections.map { "\"\($0)\"" }.joined(separator: ", ") + "."

        // Book context (when the session is tied to a book) disambiguates the *sense* of the word —
        // it must NEVER replace a valid word with a thematically-related one (the "suicide" →
        // "Sisyphe" failure). So it is applied only at the define step, after the word is decided.
        let bookClause: String = {
            guard let raw = bookContext?.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return "" }
            return " The reader is reading \"\(raw)\"; use that ONLY to pick the most fitting sense — never to change which word is defined."
        }()

        // The transcription is a *hypothesis*, not ground truth: on the iOS 26 DictationTranscriber
        // path only one candidate comes back, and the reader is non-native, so phonetic misfires are
        // systematic. Let Claude correct the word before defining it (same single call, no extra
        // latency). The keep-if-valid guard is deliberately strict so a valid word is never swapped
        // for a book-themed one; corrections must be driven by sound, not topic. The reader may also
        // speak a short phrase (e.g. "mal de l'esprit"), so accept an expression, not just one word.
        let prompt = """
        Someone reading aloud in \(sourceLanguage) (not a native \(sourceLanguage) speaker) spoke a word or short phrase that on-device speech recognition transcribed as "\(word)". The transcription may be phonetically inaccurate.

        Decide the most likely intended \(sourceLanguage) word or expression:
        - If "\(word)" is already a valid \(sourceLanguage) word or expression, keep it EXACTLY — even if a different word would fit the book's theme better. Only change it to fix a clear phonetic mishearing.
        - Otherwise infer the most likely intended \(sourceLanguage) word or expression that SOUNDS like the transcription — not merely one related to the book.\(rejectedClause)

        Then define it in \(targetLanguage).\(bookClause) Reply with ONLY a JSON object, no markdown, no extra text. Replace each angle-bracket placeholder with a real value:
        {"correctedWord": "<the intended \(sourceLanguage) word or expression>", "definition": "<short definition>", "exampleSentence": "<example sentence>"}
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
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

        // Extract the text content from the Messages API envelope
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

    // Pure, `nonisolated static` so it's unit-testable without a network round-trip. Strips any
    // markdown fences, decodes the JSON object, and normalizes `correctedWord` (blank or a
    // case-insensitive match of the original transcription collapses to `nil` = no correction).
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
            correctedWord: normalizeCorrection(decoded.correctedWord, original: original)
        )
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
        // Strip markdown code fences if present
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Find the first { and last } and take just that range
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
