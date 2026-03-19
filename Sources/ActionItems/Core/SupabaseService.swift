import Foundation
import Supabase

/// Supabase integration — syncs action items across team members in real-time.
class SupabaseService: ObservableObject {
    @Published var isConnected = false
    @Published var isSyncing = false
    @Published var teamId: String?

    var onItemUpdate: (() -> Void)?

    private var client: SupabaseClient?
    private var realtimeTask: Task<Void, Never>?

    static var supabaseURL: String {
        get { UserDefaults.standard.string(forKey: "supabase_url") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "supabase_url") }
    }

    static var supabaseAnonKey: String {
        get { UserDefaults.standard.string(forKey: "supabase_anon_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "supabase_anon_key") }
    }

    var isConfigured: Bool {
        !Self.supabaseURL.isEmpty && !Self.supabaseAnonKey.isEmpty
    }

    // MARK: - Encodable row types for Supabase

    private struct ActionItemRow: Encodable {
        var id: String?
        var team_id: String
        var task: String
        var status: String
        var source: String
        var source_detail: String
        var meeting_title: String?
        var meeting_date: String?
        var deadline: String?
        var deadline_date: String?
        var assigned_to: String?
        var assigned_by: String?
        var participants: String?
        var nudge_count: Int
    }

    private struct TeamRow: Encodable {
        var name: String
    }

    private struct UserRow: Encodable {
        var team_id: String
        var name: String
        var email: String?
        var slack_user_id: String?
    }

    private struct StatusUpdate: Encodable {
        var status: String
    }

    // MARK: - Setup

    func setup() {
        guard isConfigured,
              let url = URL(string: Self.supabaseURL) else { return }

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: Self.supabaseAnonKey
        )
        teamId = UserDefaults.standard.string(forKey: "supabase_team_id")
        isConnected = true
        subscribeToUpdates()
    }

    func teardown() {
        realtimeTask?.cancel()
        realtimeTask = nil
        client = nil
        isConnected = false
    }

    // MARK: - Sync

    func syncItem(_ item: ActionItem) async throws {
        guard let client, let teamId else { return }
        await MainActor.run { isSyncing = true }
        defer { Task { @MainActor in self.isSyncing = false } }

        let iso = ISO8601DateFormatter()
        let row = ActionItemRow(
            id: item.supabaseId,
            team_id: teamId,
            task: item.task,
            status: item.status.rawValue,
            source: item.source.rawValue,
            source_detail: item.sourceDetail,
            meeting_title: item.meetingTitle,
            meeting_date: item.meetingDate.map { iso.string(from: $0) },
            deadline: item.deadline,
            deadline_date: item.deadlineDate.map { iso.string(from: $0) },
            assigned_to: item.assignedToJson,
            assigned_by: item.assignedByJson,
            participants: item.participantsJson,
            nudge_count: item.nudgeCount
        )

        try await client
            .from("action_items")
            .upsert(row)
            .execute()
    }

    func fetchTeamItems() async throws -> [AnyJSON] {
        guard let client, let teamId else { return [] }
        let response = try await client
            .from("action_items")
            .select()
            .eq("team_id", value: teamId)
            .order("created_at", ascending: false)
            .execute()
        return []  // Decode response.data as needed
    }

    func updateStatus(supabaseId: String, status: ItemStatus) async throws {
        guard let client else { return }
        let update = StatusUpdate(status: status.rawValue)
        try await client
            .from("action_items")
            .update(update)
            .eq("id", value: supabaseId)
            .execute()
    }

    // MARK: - Realtime

    private func subscribeToUpdates() {
        guard let client, let teamId else { return }

        realtimeTask = Task {
            let channel = await client.realtimeV2.channel("action_items:\(teamId)")

            await channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: "action_items",
                filter: "team_id=eq.\(teamId)"
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.onItemUpdate?() }
            }

            await channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: "action_items",
                filter: "team_id=eq.\(teamId)"
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.onItemUpdate?() }
            }

            await channel.subscribe()
        }
    }

    // MARK: - Team management

    func createTeam(name: String, currentUser: Person) async throws -> String {
        guard let client else { throw SupabaseError.notConfigured }

        let teamRow = TeamRow(name: name)
        let response = try await client
            .from("teams")
            .insert(teamRow)
            .select()
            .single()
            .execute()

        // Extract ID from response data
        guard let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let newTeamId = json["id"] as? String else {
            throw SupabaseError.noTeamId
        }

        UserDefaults.standard.set(newTeamId, forKey: "supabase_team_id")
        teamId = newTeamId
        try await registerUser(currentUser, teamId: newTeamId)
        return newTeamId
    }

    func registerUser(_ user: Person, teamId: String) async throws {
        guard let client else { return }
        let userRow = UserRow(
            team_id: teamId,
            name: user.name,
            email: user.email,
            slack_user_id: user.slackUserId
        )
        try await client
            .from("users")
            .upsert(userRow, onConflict: "email")
            .execute()
    }

    // MARK: - Wake reconnect

    func reconnect() {
        teardown()
        setup()
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case notConfigured
    case noTeamId

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase not configured. Go to Settings → Integrations."
        case .noTeamId:      return "Could not create team ID."
        }
    }
}
