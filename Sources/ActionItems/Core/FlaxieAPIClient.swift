import Foundation
import AppKit

/// All communication with the Flaxie FastAPI backend goes through here.
/// The desktop app holds only a JWT — no Supabase keys, no Claude key.
class FlaxieAPIClient: ObservableObject {
    static let shared = FlaxieAPIClient()

    // Change this to your deployed backend URL
    private let baseURL = URL(string: "http://localhost:8000")!

    @Published var isAuthenticated = false

    private var token: String? {
        get { UserDefaults.standard.string(forKey: "flaxie_jwt") }
        set { UserDefaults.standard.set(newValue, forKey: "flaxie_jwt") }
    }

    var userId: String? {
        UserDefaults.standard.string(forKey: "flaxie_user_id")
    }

    // MARK: - Auth

    func register(deviceId: String, name: String, email: String?) async throws -> AuthResponse {
        let body = DeviceRegisterBody(device_id: deviceId, name: name, email: email)
        let resp: AuthResponse = try await post("/auth/device", body: body, authenticated: false)
        token = resp.token
        UserDefaults.standard.set(resp.user_id, forKey: "flaxie_user_id")
        UserDefaults.standard.set(resp.team_id, forKey: "flaxie_team_id")
        await MainActor.run { isAuthenticated = true }
        return resp
    }

    // MARK: - Notes

    func processNotes(rawNotes: String, meetingTitle: String, source: String) async throws -> ProcessNotesResponse {
        let body = ProcessNotesBody(raw_notes: rawNotes, meeting_title: meetingTitle, source: source)
        return try await post("/notes/process", body: body)
    }

    // MARK: - Items

    func fetchItems() async throws -> [APIActionItem] {
        return try await get("/items")
    }

    func updateItemStatus(id: String, status: String) async throws -> APIActionItem {
        return try await patch("/items/\(id)", body: ItemUpdateBody(status: status))
    }

    func deleteItem(id: String) async throws {
        let _: EmptyResponse = try await delete("/items/\(id)")
    }

    func generateDraft(item: ActionItem, draftType: String) async throws -> DraftResponse {
        // Treat empty string supabaseId as nil (pipeline returns "" for unsaved items)
        let effectiveId = item.supabaseId.flatMap { $0.isEmpty ? nil : $0 }
        let body = DraftRequestBody(
            item_id: effectiveId,
            draft_type: draftType,
            task: item.task,                    // always send task as fallback
            assigned_to_name: item.assignedTo?.name,
            deadline: item.deadline,
            meeting_title: item.meetingTitle
        )
        return try await post("/items/draft", body: body)
    }

    // MARK: - Teams

    func createTeam(name: String) async throws -> TeamResponse {
        return try await post("/teams/create", body: CreateTeamBody(name: name))
    }

    func joinTeam(joinCode: String) async throws -> TeamResponse {
        return try await post("/teams/join", body: JoinTeamBody(join_code: joinCode))
    }

    func getMyTeam() async throws -> TeamResponse {
        return try await get("/teams/me")
    }

    // MARK: - Nudge

    func sendNudge(itemId: String, channel: String, customMessage: String? = nil) async throws {
        let body = NudgeBody(item_id: itemId, channel: channel, custom_message: customMessage)
        let _: [String: Bool] = try await post("/nudge/send", body: body)
    }

    func fetchPendingNudges() async throws -> PendingNudgesResponse {
        return try await get("/nudge/pending")
    }

    // MARK: - Slack

    func connectSlack() {
        guard let userId else { return }
        let url = URL(string: "\(baseURL.absoluteString)/slack/connect?user_id=\(userId)")!
        NSWorkspace.shared.open(url)
    }

    func fetchSlackToken() async throws -> String {
        guard let userId else { throw APIError.serverError("Not authenticated") }
        let resp: SlackTokenResponse = try await get("/slack/token?user_id=\(userId)")
        return resp.bot_token
    }

    // MARK: - Gmail

    func connectGmail() {
        guard let userId else { return }
        let url = URL(string: "\(baseURL.absoluteString)/gmail/connect?user_id=\(userId)")!
        NSWorkspace.shared.open(url)
    }

    func fetchGmailTokens() async throws -> GmailTokensResponse {
        guard let userId else { throw APIError.serverError("Not authenticated") }
        return try await get("/gmail/tokens?user_id=\(userId)")
    }

    func refreshGmailToken(refreshToken: String) async throws -> String {
        let body = GmailRefreshBody(refresh_token: refreshToken)
        let resp: GmailRefreshResponse = try await post("/gmail/refresh", body: body)
        return resp.access_token
    }

    func disconnectGmail() async throws {
        guard let userId else { return }
        let _: EmptyResponse = try await delete("/gmail/disconnect?user_id=\(userId)")
    }

    // MARK: - HTTP helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "GET"
        addAuth(&req)
        return try await send(req)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B, authenticated: Bool = true) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        if authenticated { addAuth(&req) }
        return try await send(req)
    }

    private func patch<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        addAuth(&req)
        return try await send(req)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "DELETE"
        addAuth(&req)
        return try await send(req)
    }

    private func addAuth(_ req: inout URLRequest) {
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail ?? "HTTP \(http.statusCode)"
            throw APIError.serverError(msg)
        }
        let decoder = JSONDecoder()
        // Supabase/FastAPI return dates in various ISO8601 formats — parse them all.
        decoder.dateDecodingStrategy = .custom { dec in
            let str = try dec.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            // 1. With fractional seconds + timezone (Supabase: "2024-01-01T00:00:00.000000+00:00")
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) { return date }
            // 2. With timezone, no fractional seconds ("2024-01-01T00:00:00Z")
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: str) { return date }
            // 3. No timezone (Python datetime.utcnow(): "2024-01-01T00:00:00")
            formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
            if let date = formatter.date(from: str) { return date }
            // 4. With fractional seconds, no timezone ("2024-01-01T00:00:00.123456")
            formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: try dec.singleValueContainer(),
                debugDescription: "Cannot parse date: \(str)")
        }
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Request / Response types

struct SlackTokenResponse: Decodable { var bot_token: String }
struct GmailTokensResponse: Decodable { var access_token: String?; var refresh_token: String? }
struct GmailRefreshBody: Encodable { var refresh_token: String }
struct GmailRefreshResponse: Decodable { var access_token: String }

struct DeviceRegisterBody: Encodable { var device_id: String; var name: String; var email: String? }
struct ProcessNotesBody: Encodable { var raw_notes: String; var meeting_title: String; var source: String }
struct ItemUpdateBody: Encodable { var status: String? }
struct DraftRequestBody: Encodable {
    var item_id: String?
    var draft_type: String
    var task: String?
    var assigned_to_name: String?
    var deadline: String?
    var meeting_title: String?
}
struct CreateTeamBody: Encodable { var name: String }
struct JoinTeamBody: Encodable { var join_code: String }
struct NudgeBody: Encodable { var item_id: String; var channel: String; var custom_message: String? }
struct EmptyResponse: Decodable {}
struct ErrorBody: Decodable { var detail: String }

struct AuthResponse: Decodable {
    var token: String
    var user_id: String
    var team_id: String?
    var team_join_code: String?
}

struct ProcessNotesResponse: Decodable {
    var items: [APIActionItem]
    var meeting_title: String
    var item_count: Int
}

struct TeamResponse: Decodable {
    var id: String
    var name: String
    var join_code: String
    var member_count: Int
}

struct DraftResponse: Decodable {
    var draft: String
    var draft_type: String
}

struct PendingNudgesResponse: Decodable {
    var items: [APIActionItem]
}

struct APIActionItem: Decodable {
    var id: String
    var task: String
    var status: String
    var source: String
    var meeting_title: String?
    var deadline: String?
    var deadline_date: Date?
    var assigned_to: APIPerson?
    var assigned_by: APIPerson?
    var nudge_count: Int
    var confidence: Double
    var ai_draft_email: String?
    var ai_draft_slack: String?
    var created_at: Date
    var updated_at: Date
}

struct APIPerson: Decodable {
    var name: String
    var email: String?
    var slack_user_id: String?
    var is_current_user: Bool?
}

enum APIError: LocalizedError {
    case serverError(String)
    var errorDescription: String? {
        if case .serverError(let msg) = self { return msg }
        return nil
    }
}
