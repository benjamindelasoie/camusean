import Foundation

struct LookupResult {
    let definition: String
    let exampleSentence: String
}

actor AnthropicService {
    private let model = "claude-haiku-4-5-20251001"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let dailyCap = 200
    private var dailyCount = 0
    private var lastResetDate = Calendar.current.startOfDay(for: Date())

    func lookup(word: String, sourceLanguage: String, targetLanguage: String, apiKey: String) async throws -> LookupResult {
        resetDailyCountIfNeeded()
        guard dailyCount < dailyCap else { throw LookupError.dailyCapReached }

        let prompt = """
        Define the \(sourceLanguage) word "\(word)" in \(targetLanguage).
        Reply with ONLY a JSON object, no markdown, no extra text:
        {"definition": "short definition here", "exampleSentence": "example using the word"}
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

        // Claude sometimes wraps JSON in markdown fences — strip them and find the object
        let extracted = extractJSON(from: text)
        guard
            let jsonData = extracted.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
            let definition = obj["definition"],
            let exampleSentence = obj["exampleSentence"]
        else { throw LookupError.malformedResponse("couldn't parse JSON: \(extracted)") }

        dailyCount += 1
        return LookupResult(definition: definition, exampleSentence: exampleSentence)
    }

    private func extractJSON(from text: String) -> String {
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
