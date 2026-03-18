import Foundation
import AppKit
import Network

/// Gmail integration via OAuth 2.0 + REST API (read-only scope).
/// Uses a local HTTP server to receive the OAuth callback (required for Desktop app credentials).
class GmailService: ObservableObject {
    @Published var isConnected = false
    @Published var lastSyncDate: Date?

    private var clientID: String { UserDefaults.standard.string(forKey: "gmail_client_id") ?? "" }
    private let scope = "https://www.googleapis.com/auth/gmail.readonly"
    private let tokenKey = "gmail_access_token"
    private let refreshKey = "gmail_refresh_token"
    private let processedIDsKey = "gmail_processed_ids"
    private var oauthServer: LocalOAuthServer?

    var accessToken: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: refreshKey) }
        set { UserDefaults.standard.set(newValue, forKey: refreshKey) }
    }

    // IDs of emails already processed — persisted to avoid duplicates across launches
    private var processedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: processedIDsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: processedIDsKey) }
    }

    init() {
        // Restore connected state — if we have a stored token, we're connected
        isConnected = UserDefaults.standard.string(forKey: tokenKey) != nil
    }

    // MARK: - OAuth Flow

    func startOAuthFlow() {
        guard !clientID.isEmpty else {
            print("Gmail client ID not set in Settings")
            return
        }

        let server = LocalOAuthServer()
        oauthServer = server

        do {
            try server.start()
        } catch {
            print("Failed to start local OAuth server: \(error)")
            return
        }

        let port = server.assignedPort
        let redirectURI = "http://localhost:\(port)/callback"

        server.onCode = { [weak self] code in
            guard let self else { return }
            Task {
                try? await self.exchangeCodeForTokens(code: code, redirectURI: redirectURI)
                self.oauthServer = nil
            }
        }

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    /// No longer needed — kept for potential other URL-scheme uses
    func handleCallback(url: URL) {
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else { return }
        Task {
            // redirectURI won't match but this path is now unused for Gmail
            _ = code
        }
    }

    private func exchangeCodeForTokens(code: String, redirectURI: String) async throws {
        let clientSecret = UserDefaults.standard.string(forKey: "gmail_client_secret") ?? ""

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        accessToken = json?["access_token"] as? String
        refreshToken = json?["refresh_token"] as? String ?? refreshToken

        await MainActor.run { isConnected = true }
    }

    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else { throw GmailError.notAuthenticated }
        let clientSecret = UserDefaults.standard.string(forKey: "gmail_client_secret") ?? ""
        let clientID = UserDefaults.standard.string(forKey: "gmail_client_id") ?? ""

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token": refresh,
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "refresh_token"
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        accessToken = json?["access_token"] as? String
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
            // Skip emails already processed in a previous poll
            guard !seen.contains(id) else { continue }

            if let email = try? await fetchEmail(id: id, token: accessToken ?? "") {
                results.append(email)
                seen.insert(id)
            }
        }

        // Persist updated processed IDs (cap at 500 to avoid unbounded growth)
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

    /// Returns the user's reply text if they replied after `afterMessageId` in the thread, nil if no reply.
    func fetchThreadReply(threadId: String, afterMessageId: String, userEmail: String) async -> String? {
        guard let token = accessToken, !userEmail.isEmpty else { return nil }
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadId)?format=full")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return nil }

        // Find the index of the original message
        guard let originIndex = messages.firstIndex(where: { ($0["id"] as? String) == afterMessageId }) else { return nil }

        // Look for any message after it where the From header matches the user
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
    }
}

// MARK: - Local HTTP server for OAuth callback

private class LocalOAuthServer {
    private var listener: NWListener?
    private(set) var assignedPort: UInt16 = 0
    var onCode: ((String) -> Void)?

    func start() throws {
        let semaphore = DispatchSemaphore(value: 0)

        listener = try NWListener(using: .tcp, on: .any)

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.assignedPort = self?.listener?.port?.rawValue ?? 0
                semaphore.signal()
            case .failed:
                semaphore.signal()
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        listener?.start(queue: .global(qos: .userInitiated))
        semaphore.wait()
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else { return }

            // Parse: GET /callback?code=XXX HTTP/1.1
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let pathPart = firstLine.components(separatedBy: " ").dropFirst().first ?? ""

            if let url = URL(string: "http://localhost" + pathPart),
               let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                   .queryItems?.first(where: { $0.name == "code" })?.value {

                let html = "<html><body style='font-family:system-ui;text-align:center;padding:60px'><h2>✅ Gmail connected!</h2><p>You can close this tab and return to Action Items.</p></body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                    connection.cancel()
                }))

                self?.onCode?(code)
                self?.stop()
            }
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
