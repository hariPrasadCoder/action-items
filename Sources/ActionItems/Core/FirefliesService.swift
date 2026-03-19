import Foundation

/// Fireflies.ai integration — polls for new transcripts via GraphQL API.
class FirefliesService: ObservableObject {
    @Published var isConnected = false
    @Published var lastSyncDate: Date?

    var onTranscriptReady: ((String, String?, Date?) -> Void)?

    private var pollingTimer: Timer?
    private var processedIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "fireflies_processed_ids") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "fireflies_processed_ids") }
    }

    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: "fireflies_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "fireflies_api_key") }
    }

    var hasKey: Bool { !Self.apiKey.isEmpty }

    // MARK: - Polling

    func startPolling(intervalMinutes: Int = 30) {
        guard hasKey else { return }
        Task { await sync() }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalMinutes * 60), repeats: true) { [weak self] _ in
            Task { await self?.sync() }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Sync

    func sync() async {
        guard hasKey else { return }

        do {
            let transcripts = try await fetchRecentTranscripts(hours: 24)
            var ids = processedIds

            for transcript in transcripts {
                guard !ids.contains(transcript.id) else { continue }
                ids.insert(transcript.id)

                let text = buildTranscriptText(transcript)
                guard !text.isEmpty else { continue }

                let meetingDate = transcript.dateString.flatMap { parseDate($0) }

                DispatchQueue.main.async { [weak self] in
                    self?.lastSyncDate = Date()
                    self?.onTranscriptReady?(text, transcript.title, meetingDate)
                }
            }

            if ids.count > 500 { ids = Set(ids.prefix(400)) }
            processedIds = ids

            await MainActor.run { isConnected = true }
        } catch {
            print("[Fireflies] Sync error: \(error)")
            await MainActor.run { isConnected = false }
        }
    }

    // MARK: - GraphQL

    private func fetchRecentTranscripts(hours: Int) async throws -> [FirefliesTranscript] {
        let query = """
        {
          transcripts(limit: 10) {
            id
            title
            date
            sentences {
              speaker_name
              text
            }
            summary {
              action_items
              overview
            }
          }
        }
        """

        var request = URLRequest(url: URL(string: "https://api.fireflies.ai/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let transcriptsJson = (json?["data"] as? [String: Any])?["transcripts"] as? [[String: Any]] ?? []

        return transcriptsJson.compactMap { FirefliesTranscript(json: $0) }
    }

    private func buildTranscriptText(_ transcript: FirefliesTranscript) -> String {
        var parts: [String] = []
        if let title = transcript.title { parts.append("Meeting: \(title)") }
        if let date = transcript.dateString { parts.append("Date: \(date)") }

        // Add summary action items if available
        if let actionItems = transcript.summaryActionItems, !actionItems.isEmpty {
            parts.append("Action Items Summary: \(actionItems)")
        }

        // Add speaker transcript
        let sentences = transcript.sentences.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        if !sentences.isEmpty { parts.append(sentences) }

        return parts.joined(separator: "\n\n")
    }

    private func parseDate(_ string: String) -> Date? {
        // Fireflies returns millisecond timestamps or ISO strings
        if let ms = Double(string) {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }

    // MARK: - Test connection

    func testConnection() async throws {
        let _ = try await fetchRecentTranscripts(hours: 1)
        await MainActor.run { isConnected = true }
    }
}

// MARK: - Models

private struct FirefliesTranscript {
    let id: String
    let title: String?
    let dateString: String?
    let sentences: [(speaker: String, text: String)]
    let summaryActionItems: String?

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        self.title = json["title"] as? String
        self.dateString = (json["date"] as? Int).map { String($0) } ?? json["date"] as? String

        let sentencesJson = json["sentences"] as? [[String: Any]] ?? []
        self.sentences = sentencesJson.compactMap { s in
            guard let speaker = s["speaker_name"] as? String,
                  let text = s["text"] as? String else { return nil }
            return (speaker: speaker, text: text)
        }

        let summary = json["summary"] as? [String: Any]
        self.summaryActionItems = summary?["action_items"] as? String
    }
}
