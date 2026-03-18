import Foundation

// Renamed internally to use Anthropic/Claude, but keeping filename for compatibility
struct KimiService {
    static let baseURL = "https://api.anthropic.com/v1/messages"
    static let anthropicVersion = "2023-06-01"

    static var apiKey: String {
        UserDefaults.standard.string(forKey: "kimi_api_key") ?? ""
    }

    static var model: String {
        UserDefaults.standard.string(forKey: "kimi_model") ?? "claude-haiku-4-5-20251001"
    }

    // MARK: - Core chat completion (Anthropic Messages API)

    static func complete(systemPrompt: String, userMessage: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw KimiError.noAPIKey
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KimiError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 {
                throw KimiError.invalidKey
            }
            throw KimiError.apiError(httpResponse.statusCode, errorText)
        }

        // Anthropic response: {"content": [{"type": "text", "text": "..."}]}
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        let text = content?.first(where: { $0["type"] as? String == "text" })?["text"] as? String

        guard let text else {
            throw KimiError.parseError("No text in response")
        }

        return text
    }

    // MARK: - Action item extraction

    static func extractActionItems(from text: String, context: String = "") async throws -> [ExtractedActionItem] {
        let systemPrompt = """
        You are a precise action item extractor focused on messaging and communication apps (Slack, WhatsApp, Gmail, iMessage, Teams, etc.).

        Your job: extract ONLY genuine, concrete action items that require someone to actually do something.

        EXTRACT if:
        - Someone is explicitly asking YOU (the reader/viewer) to do something ("can you send...", "please review...", "don't forget to...")
        - A clear task is assigned to a specific person by name
        - There's a concrete commitment or follow-up ("I'll send you...", "let me know if...")
        - A deadline or time-sensitive request is present

        DO NOT EXTRACT:
        - Casual conversation, greetings, small talk ("sounds good", "thanks", "sure")
        - Opinions, reactions, or status updates ("I think...", "looks great", "it's done")
        - Questions without a clear action ("what do you think?", "how are you?")
        - Vague or hypothetical statements ("we should maybe...", "someday we could...")
        - Announcements or FYIs with no required action
        - Anything already marked as done or completed

        Be conservative — if you're unsure whether something is a real action item, skip it.
        A good action item is specific, assigned, and actionable.

        Return valid JSON only, no markdown, no explanation.
        Output format: [{"task": "...", "deadline": "..." or null}]
        If nothing qualifies, return: []
        """

        let userMessage = context.isEmpty
            ? text
            : "Context: \(context)\n\nText:\n\(text)"

        let response = try await complete(systemPrompt: systemPrompt, userMessage: userMessage)

        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw KimiError.parseError("Could not encode response")
        }

        return try JSONDecoder().decode([ExtractedActionItem].self, from: data)
    }
}

enum KimiError: LocalizedError {
    case noAPIKey
    case invalidKey
    case invalidResponse
    case apiError(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Anthropic API key not set. Go to Settings → API."
        case .invalidKey:
            return "Anthropic API key invalid. Check Settings → API."
        case .invalidResponse:
            return "Invalid response from Anthropic API"
        case .apiError(let code, let msg):
            return "API error \(code): \(msg)"
        case .parseError(let msg):
            return "Failed to parse response: \(msg)"
        }
    }
}
