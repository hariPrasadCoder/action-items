import Foundation

/// Slack Bot integration — sends nudges, DMs, and reads workspace members.
/// Requires a Slack Bot Token (xoxb-...) with scopes:
/// chat:write, im:write, users:read, users:read.email
class SlackService: ObservableObject {
    @Published var isConnected = false
    @Published var workspaceName: String?
    @Published var workspaceMembers: [Person] = []

    private let tokenKey = "slack_bot_token"
    private let baseURL = "https://slack.com/api"

    var botToken: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    var hasToken: Bool { botToken != nil }

    // MARK: - Connect / Disconnect

    func connect(token: String) async throws {
        // Verify token with auth.test
        let result = try await apiCall(method: "auth.test", params: [:], token: token)
        guard let ok = result["ok"] as? Bool, ok else {
            let error = result["error"] as? String ?? "Unknown error"
            throw SlackError.apiError(error)
        }

        botToken = token
        let teamName = result["team"] as? String
        await MainActor.run {
            isConnected = true
            workspaceName = teamName
        }

        // Load workspace members
        try await fetchWorkspaceMembers()
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        DispatchQueue.main.async {
            self.isConnected = false
            self.workspaceName = nil
            self.workspaceMembers = []
        }
    }

    // MARK: - Send DM

    func sendDM(to slackUserId: String, message: String) async throws {
        guard let token = botToken else { throw SlackError.noToken }

        // Open DM channel
        let imResult = try await apiCall(method: "conversations.open", params: ["users": slackUserId], token: token)
        guard let channel = (imResult["channel"] as? [String: Any])?["id"] as? String else {
            throw SlackError.apiError("Could not open DM channel")
        }

        // Send message
        let result = try await apiCall(method: "chat.postMessage", params: [
            "channel": channel,
            "text": message,
            "username": "Flaxie",
            "icon_emoji": ":robot_face:"
        ], token: token)

        guard let ok = result["ok"] as? Bool, ok else {
            throw SlackError.apiError(result["error"] as? String ?? "Send failed")
        }
    }

    func sendNudge(to person: Person, for item: ActionItem) async throws {
        guard let slackId = person.slackUserId else {
            // Try to look up by email
            if let email = person.email {
                if let found = try? await lookupUser(byEmail: email) {
                    let nudgeMessage = buildNudgeMessage(for: item, assigneeName: person.name)
                    try await sendDM(to: found, message: nudgeMessage)
                    return
                }
            }
            throw SlackError.userNotFound(person.name)
        }
        let nudgeMessage = buildNudgeMessage(for: item, assigneeName: person.name)
        try await sendDM(to: slackId, message: nudgeMessage)
    }

    private func buildNudgeMessage(for item: ActionItem, assigneeName: String) -> String {
        var msg = "Hey \(assigneeName) 👋 Just a heads-up from *Flaxie*:\n\n"
        msg += "> \(item.task)\n\n"
        if let deadline = item.deadlineDisplayText {
            msg += "This was due *\(deadline)*. "
        }
        msg += "Any updates or blockers? You can reply here or mark it done."
        return msg
    }

    // MARK: - Look up user

    func lookupUser(byEmail email: String) async throws -> String? {
        guard let token = botToken else { throw SlackError.noToken }
        let result = try await apiCall(method: "users.lookupByEmail", params: ["email": email], token: token)
        return (result["user"] as? [String: Any])?["id"] as? String
    }

    // MARK: - Workspace members

    func fetchWorkspaceMembers() async throws {
        guard let token = botToken else { throw SlackError.noToken }
        let result = try await apiCall(method: "users.list", params: ["limit": "200"], token: token)

        guard let members = result["members"] as? [[String: Any]] else { return }

        let people: [Person] = members.compactMap { member in
            guard let id = member["id"] as? String,
                  let isBot = member["is_bot"] as? Bool, !isBot,
                  id != "USLACKBOT" else { return nil }

            let profile = member["profile"] as? [String: Any]
            let name = profile?["real_name"] as? String ?? member["name"] as? String ?? id
            let email = profile?["email"] as? String

            return Person(name: name, email: email, slackUserId: id)
        }

        await MainActor.run { workspaceMembers = people }
    }

    // MARK: - API helper

    private func apiCall(method: String, params: [String: Any], token: String) async throws -> [String: Any] {
        var components = URLComponents(string: "\(baseURL)/\(method)")!
        let queryItems = params.map { URLQueryItem(name: $0.key, value: "\($0.value)") }

        // Use POST for methods that send data, GET for reads
        let postMethods = ["chat.postMessage", "conversations.open"]
        let usePost = postMethods.contains(method)

        var request: URLRequest
        if usePost {
            request = URLRequest(url: URL(string: "\(baseURL)/\(method)")!)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        } else {
            components.queryItems = queryItems
            request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

}

// MARK: - Errors

enum SlackError: LocalizedError {
    case noToken
    case apiError(String)
    case userNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noToken:            return "Slack bot token not configured. Go to Settings → Integrations."
        case .apiError(let msg):  return "Slack error: \(msg)"
        case .userNotFound(let n): return "Could not find Slack user for \(n)"
        }
    }
}
