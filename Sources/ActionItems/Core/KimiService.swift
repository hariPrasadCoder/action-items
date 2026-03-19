import Foundation

// Claude/Anthropic API wrapper — extracts action items and drafts messages
struct KimiService {
    static let baseURL = "https://api.anthropic.com/v1/messages"
    static let anthropicVersion = "2023-06-01"

    static var apiKey: String {
        UserDefaults.standard.string(forKey: "kimi_api_key") ?? ""
    }

    static var model: String {
        UserDefaults.standard.string(forKey: "kimi_model") ?? "claude-haiku-4-5-20251001"
    }

    // MARK: - Core completion

    static func complete(systemPrompt: String, userMessage: String) async throws -> String {
        guard !apiKey.isEmpty else { throw KimiError.noAPIKey }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMessage]]
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw KimiError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 { throw KimiError.invalidKey }
            throw KimiError.apiError(httpResponse.statusCode, errorText)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        let text = content?.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        guard let text else { throw KimiError.parseError("No text in response") }
        return text
    }

    // MARK: - People-aware action item extraction (primary)

    static func extractActionItemsWithPeople(
        from text: String,
        context: String = "",
        currentUserName: String = ""
    ) async throws -> [ExtractedActionItem] {
        let userHint = currentUserName.isEmpty ? "" : " The current user's name is \(currentUserName)."

        let systemPrompt = """
        You are Flaxie, an intelligent meeting action taker.\(userHint)

        Analyze the provided text (meeting notes, transcript, email, or screen capture) and extract concrete action items with ownership.

        For each action item, identify:
        - "task": The specific thing to be done (clear and actionable)
        - "assigned_to": The person responsible (use their name exactly as mentioned, or null if unclear)
        - "assigned_by": Who gave this task or made the request (use their name, or null)
        - "deadline": Any mentioned deadline or timeframe (e.g. "Wednesday", "EOD", "next Friday"), or null
        - "confidence": Your confidence this is a real action item (0.0-1.0)

        EXTRACT if:
        - Someone explicitly commits to doing something ("I'll send...", "I will review...")
        - Someone is asked to do something by name ("Alex, can you...")
        - A clear deliverable with a deadline is mentioned
        - A follow-up action is needed after the conversation

        DO NOT EXTRACT:
        - Casual conversation, greetings, opinions
        - Status updates that are already done
        - Vague hypotheticals ("maybe we should...")
        - Announcements with no required action

        Return valid JSON only, no markdown, no explanation.
        Format: [{"task": "...", "assigned_to": "name or null", "assigned_by": "name or null", "deadline": "... or null", "confidence": 0.9}]
        If nothing qualifies, return: []
        """

        let userMessage = context.isEmpty ? text : "Context: \(context)\n\nText:\n\(text)"
        let response = try await complete(systemPrompt: systemPrompt, userMessage: userMessage)
        return try parseExtracted(response)
    }

    // MARK: - Simple extraction (for screen capture, Gmail — no speaker context)

    static func extractActionItems(from text: String, context: String = "") async throws -> [ExtractedActionItem] {
        let systemPrompt = """
        You are Flaxie, an intelligent action item extractor.

        Extract ONLY genuine, concrete action items that require someone to actually do something.

        EXTRACT if:
        - Someone is explicitly asking the reader to do something
        - A clear task is assigned to a specific person by name
        - There's a concrete commitment or follow-up with a deadline
        - A time-sensitive request is present

        DO NOT EXTRACT:
        - Casual conversation, greetings, small talk
        - Opinions, reactions, or status updates
        - Questions without a clear action
        - Vague or hypothetical statements
        - Anything already marked as done

        Return valid JSON only, no markdown, no explanation.
        Format: [{"task": "...", "assigned_to": null, "assigned_by": null, "deadline": "... or null", "confidence": 0.9}]
        If nothing qualifies, return: []
        """

        let userMessage = context.isEmpty ? text : "Context: \(context)\n\nText:\n\(text)"
        let response = try await complete(systemPrompt: systemPrompt, userMessage: userMessage)
        return try parseExtracted(response)
    }

    // MARK: - Draft message

    static func draftMessage(for item: ActionItem, type: AIDraftType) async throws -> String {
        let typeLabel = type == .email ? "email" : "Slack message"
        let context = [
            item.meetingTitle.map { "Meeting: \($0)" },
            item.sourceDetail.isEmpty ? nil : "Source: \(item.sourceDetail)",
            item.deadline.map { "Deadline: \($0)" },
            item.assignedTo.map { "For: \($0.name)" }
        ].compactMap { $0 }.joined(separator: "\n")

        let systemPrompt = """
        You are Flaxie, a professional AI assistant. Draft a concise, friendly \(typeLabel) based on the action item below.
        The message should be ready to send with minimal editing. Keep it brief and professional.
        Include a clear subject line if drafting an email. Do not add placeholders like [Name] — write naturally.
        Return only the draft text, no explanation.
        """

        let userMessage = """
        Action item: \(item.task)
        \(context)

        Draft a \(typeLabel) to follow up on this.
        """

        return try await complete(systemPrompt: systemPrompt, userMessage: userMessage)
    }

    // MARK: - Parse helper

    private static func parseExtracted(_ response: String) throws -> [ExtractedActionItem] {
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

// MARK: - Errors

enum KimiError: LocalizedError {
    case noAPIKey
    case invalidKey
    case invalidResponse
    case apiError(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:             return "Anthropic API key not set. Go to Settings → API."
        case .invalidKey:           return "Anthropic API key invalid. Check Settings → API."
        case .invalidResponse:      return "Invalid response from Anthropic API"
        case .apiError(let c, let m): return "API error \(c): \(m)"
        case .parseError(let m):    return "Failed to parse response: \(m)"
        }
    }
}
