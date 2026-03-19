import Foundation
import AppKit

/// Gmail integration via backend-mediated OAuth 2.0.
/// OAuth credentials are stored server-side; the macOS app only holds
/// the access/refresh tokens fetched from the backend after the user authorises.
class GmailService: ObservableObject {
    @Published var isConnected = false
    @Published var lastSyncDate: Date?

    private let tokenKey = "gmail_access_token"
    private let refreshKey = "gmail_refresh_token"
    private let processedIDsKey = "gmail_processed_ids"

    var accessToken: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: refreshKey) }
        set { UserDefaults.standard.set(newValue, forKey: refreshKey) }
    }

    private var processedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: processedIDsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: processedIDsKey) }
    }

    init() {
        isConnected = UserDefaults.standard.string(forKey: tokenKey) != nil
    }

    // MARK: - OAuth Flow (backend-mediated)

    /// Opens the backend /gmail/connect URL in the browser. Google redirects back
    /// to the backend, which stores the tokens and redirects to actionitems://gmail-connected.
    func startOAuthFlow() {
        FlaxieAPIClient.shared.connectGmail()
    }

    /// Called by AppDelegate when actionitems://gmail-connected is received.
    /// Fetches the stored tokens from the backend and caches them locally.
    func handleConnectedCallback() {
        Task {
            await fetchTokensFromBackend()
        }
    }

    func fetchTokensFromBackend() async {
        do {
            let tokens = try await FlaxieAPIClient.shared.fetchGmailTokens()
            accessToken = tokens.access_token
            refreshToken = tokens.refresh_token
            await MainActor.run { isConnected = true }
        } catch {
            print("[GmailService] Failed to fetch tokens from backend: \(error)")
        }
    }

    // MARK: - Token refresh (direct to Google, using stored client credentials via backend)

    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else { throw GmailError.notAuthenticated }

        // Refresh via backend so we never expose the client secret to the client
        let newToken = try await FlaxieAPIClient.shared.refreshGmailToken(refreshToken: refresh)
        accessToken = newToken
    }

    // MARK: - Fetch Emails

    func fetchRecentEmails(hours: Int = 24) async throws -> [(id: String, threadId: String, from: String, subject: String, body: String)] {
        guard let token = accessToken else { throw GmailError.notAuthenticated }

        let after = Int(Date().addingTimeInterval(-Double(hours) * 3600).timeIntervalSince1970)
        let query = "after:\(after)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let listURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=\(query)&maxResults=20")!
        var listRequest = URLRequest(url: listURL)
        listRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (listData, listResponse) = try await URLSession.shared.data(for: listRequest)

        if (listResponse as? HTTPURLResponse)?.statusCode == 401 {
            try await refreshAccessToken()
            return try await fetchRecentEmails(hours: hours)
        }

        let listJSON = try JSONSerialization.jsonObject(with: listData) as? [String: Any]
        let messages = listJSON?["messages"] as? [[String: Any]] ?? []

        var results: [(id: String, threadId: String, from: String, subject: String, body: String)] = []
        var seen = processedIDs

        for message in messages.prefix(20) {
            guard let id = message["id"] as? String else { continue }
            guard !seen.contains(id) else { continue }

            if let email = try? await fetchEmail(id: id, token: accessToken ?? "") {
                results.append(email)
                seen.insert(id)
            }
        }

        var updated = processedIDs.union(seen)
        if updated.count > 500 { updated = Set(updated.prefix(500)) }
        processedIDs = updated

        await MainActor.run { lastSyncDate = Date() }
        return results
    }

    func getUserEmail() async -> String {
        guard let token = accessToken else { return "" }
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["emailAddress"] as? String else { return "" }
        return email
    }

    func fetchThreadReply(threadId: String, afterMessageId: String, userEmail: String) async -> String? {
        guard let token = accessToken, !userEmail.isEmpty else { return nil }
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadId)?format=full")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return nil }

        guard let originIndex = messages.firstIndex(where: { ($0["id"] as? String) == afterMessageId }) else { return nil }

        let userEmailLower = userEmail.lowercased()
        for message in messages.dropFirst(originIndex + 1) {
            let payload = message["payload"] as? [String: Any]
            let headers = (payload?["headers"] as? [[String: Any]]) ?? []
            let fromHeader = headers.first(where: { ($0["name"] as? String) == "From" })?["value"] as? String ?? ""
            if fromHeader.lowercased().contains(userEmailLower) {
                let body = extractBody(from: payload)
                let snippet = message["snippet"] as? String ?? ""
                return body.isEmpty ? snippet : String(body.prefix(500))
            }
        }
        return nil
    }

    private func fetchEmail(id: String, token: String) async throws -> (id: String, threadId: String, from: String, subject: String, body: String) {
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let payload = json?["payload"] as? [String: Any]
        let headers = payload?["headers"] as? [[String: Any]] ?? []

        let subject = headers.first(where: { ($0["name"] as? String) == "Subject" })?["value"] as? String ?? "(No Subject)"
        let from = headers.first(where: { ($0["name"] as? String) == "From" })?["value"] as? String ?? "Unknown"
        let threadId = json?["threadId"] as? String ?? ""
        let body = extractBody(from: payload)

        return (id: id, threadId: threadId, from: from, subject: subject, body: body)
    }

    private func extractBody(from payload: [String: Any]?) -> String {
        guard let payload else { return "" }

        if let body = payload["body"] as? [String: Any],
           let encodedData = body["data"] as? String {
            return decodeBase64URL(encodedData)
        }

        if let parts = payload["parts"] as? [[String: Any]] {
            for part in parts {
                let mimeType = part["mimeType"] as? String ?? ""
                if mimeType == "text/plain" {
                    if let body = part["body"] as? [String: Any],
                       let encodedData = body["data"] as? String {
                        return decodeBase64URL(encodedData)
                    }
                }
            }
        }

        return ""
    }

    private func decodeBase64URL(_ string: String) -> String {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        processedIDs = []
        isConnected = false
        Task {
            _ = try? await FlaxieAPIClient.shared.disconnectGmail()
        }
    }
}

enum GmailError: LocalizedError {
    case notAuthenticated
    case fetchFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Gmail not connected. Go to Settings to connect."
        case .fetchFailed: return "Failed to fetch emails."
        }
    }
}
