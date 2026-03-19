import Foundation
import SwiftUI

class AppState: ObservableObject {
    // MARK: - Published state

    @Published var actionItems: [ActionItem] = []
    @Published var isExtracting = false
    @Published var lastError: String?
    @Published var notification: String?
    @Published var activityLog: [(Date, String)] = []

    // MARK: - Identity

    @Published var currentUser: Person = {
        let name = UserDefaults.standard.string(forKey: "current_user_name") ?? ""
        let email = UserDefaults.standard.string(forKey: "current_user_email")
        return Person(name: name, email: email, isCurrentUser: true)
    }()

    // MARK: - Services

    let gmail = GmailService()
    let calendar = CalendarService.shared
    let granola = GranolaService()
    let fireflies = FirefliesService()
    let otter = OtterService()
    let slack = SlackService()
    let supabase = SupabaseService()
    let nudgeEngine = NudgeEngine()

    private var gmailTimer: Timer?

    // MARK: - Computed

    var myItems: [ActionItem] {
        actionItems.filter { item in
            guard item.status != .done else { return false }
            guard let assignedTo = item.assignedTo else { return true }
            return assignedTo.isCurrentUser || isMe(assignedTo.name)
        }
    }

    var delegatedItems: [ActionItem] {
        actionItems.filter { item in
            guard item.status != .done else { return false }
            guard let assignedTo = item.assignedTo else { return false }
            return !assignedTo.isCurrentUser && !isMe(assignedTo.name)
        }
    }

    /// Returns true if the given name refers to the current user (case-insensitive, first-name aware).
    func isMe(_ name: String) -> Bool {
        let myName = currentUser.name.lowercased()
        guard !myName.isEmpty else { return false }
        let n = name.lowercased()
        return myName == n || myName.hasPrefix(n + " ") || n.hasPrefix(myName + " ")
    }

    var delegatedByAssignee: [(Person, [ActionItem])] {
        let grouped = Dictionary(grouping: delegatedItems) { $0.assignedTo?.name ?? "Unknown" }
        return grouped.compactMap { name, items in
            guard let person = items.first?.assignedTo else { return nil }
            return (person, items.sorted { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) })
        }.sorted { $0.0.name < $1.0.name }
    }

    var pendingCount: Int { myItems.count }
    var overdueCount: Int { myItems.filter { $0.urgency == .overdue }.count }

    // MARK: - Init

    init() {
        loadItems()
        wireServices()
    }

    // MARK: - Save current user

    func saveCurrentUser() {
        UserDefaults.standard.set(currentUser.name, forKey: "current_user_name")
        UserDefaults.standard.set(currentUser.email, forKey: "current_user_email")
    }

    // MARK: - Wire services

    private func wireServices() {
        // Granola
        granola.onNotesDetected = { [weak self] text, title, date in
            Task { await self?.processNotes(text: text, source: .granola, meetingTitle: title, meetingDate: date) }
        }

        // Fireflies
        fireflies.onTranscriptReady = { [weak self] text, title, date in
            Task { await self?.processNotes(text: text, source: .fireflies, meetingTitle: title, meetingDate: date) }
        }

        // Otter
        otter.onTranscriptReady = { [weak self] text, title, date in
            Task { await self?.processNotes(text: text, source: .otter, meetingTitle: title, meetingDate: date) }
        }

        // Supabase realtime
        supabase.onItemUpdate = { [weak self] in
            self?.loadItems()
            self?.logActivity("Team update synced from Supabase")
        }

        // Nudge engine
        nudgeEngine.start(appState: self, slackService: slack)

        // Auto-start watching if Granola is found
        if GranolaService.detectGranolaDirectory() != nil {
            granola.startWatching()
            logActivity("Granola watching started")
        }

        // Otter: always watch Downloads
        otter.startWatching()

        // Fireflies: start polling if key exists
        if fireflies.hasKey {
            fireflies.startPolling()
        }

        // Slack: check stored token
        if slack.hasToken {
            Task {
                try? await slack.fetchWorkspaceMembers()
                await MainActor.run { self.slack.isConnected = true }
            }
        }

        // Supabase
        if supabase.isConfigured {
            supabase.setup()
        }
    }

    // MARK: - Data

    func loadItems() {
        do {
            actionItems = try DatabaseManager.shared.fetchAll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Unified note processing pipeline

    func processNotes(
        text: String,
        source: ActionItemSource,
        meetingTitle: String? = nil,
        meetingDate: Date? = nil
    ) async {
        guard !isExtracting else { return }
        await MainActor.run { isExtracting = true }
        defer { Task { @MainActor in self.isExtracting = false } }

        let sourceLabel = meetingTitle ?? source.displayName
        await showNotification("Flaxie is reading \(sourceLabel)...")
        logActivity("Reading \(sourceLabel) (\(source.displayName))")

        do {
            let response = try await FlaxieAPIClient.shared.processNotes(
                rawNotes: text,
                meetingTitle: meetingTitle ?? source.displayName,
                source: source.rawValue
            )

            guard !response.items.isEmpty else {
                await showNotification("No action items found in \(sourceLabel)")
                return
            }

            // Deduplicate: build a set of existing task texts (lowercased) to skip exact matches
            let existingTaskTexts = Set(actionItems.map { $0.task.lowercased().trimmingCharacters(in: .whitespaces) })

            var savedItems: [ActionItem] = []
            for e in response.items {
                let taskKey = e.task.lowercased().trimmingCharacters(in: .whitespaces)
                guard !existingTaskTexts.contains(taskKey) else { continue }

                var item = ActionItem(
                    task: e.task,
                    source: source,
                    sourceDetail: meetingTitle ?? source.displayName,
                    status: ItemStatus(rawValue: e.status) ?? .todo,
                    deadline: e.deadline,
                    deadlineDate: e.deadline_date,
                    meetingTitle: meetingTitle,
                    meetingDate: meetingDate,
                    supabaseId: e.id
                )
                if let p = e.assigned_to {
                    item.assignedTo = Person(name: p.name, email: p.email, slackUserId: p.slack_user_id, isCurrentUser: p.is_current_user ?? false)
                }
                if let p = e.assigned_by {
                    item.assignedBy = Person(name: p.name, email: p.email, slackUserId: p.slack_user_id, isCurrentUser: p.is_current_user ?? false)
                }

                try DatabaseManager.shared.save(&item)
                NotificationManager.shared.scheduleDeadlineNotification(for: item)
                savedItems.append(item)
            }

            await MainActor.run { self.loadItems() }

            let mine = savedItems.filter { $0.assignedTo == nil || ($0.assignedTo?.isCurrentUser ?? false) }.count
            let delegated = savedItems.count - mine
            var summary = "\(savedItems.count) item\(savedItems.count == 1 ? "" : "s") from \(sourceLabel)"
            if delegated > 0 { summary += " · \(delegated) delegated" }

            await showNotification(summary)
            logActivity("Extracted \(savedItems.count) items from \(sourceLabel)")

            // Send Slack notifications for delegated items
            await notifyDelegatedViaSlack(savedItems)

        } catch {
            await showNotification("Error: \(error.localizedDescription)")
            await MainActor.run { self.lastError = error.localizedDescription }
        }
    }

    // MARK: - Screen Capture

    func captureScreenAndExtract() async {
        guard !isExtracting else { return }
        await MainActor.run { isExtracting = true }

        // Safety timeout: SCKit calls can hang indefinitely if permission is in a weird state.
        // Cancel the capture task and reset the spinner after 15 seconds.
        let captureTask = Task { await self._captureAndExtract() }
        Task {
            try? await Task.sleep(for: .seconds(15))
            if !captureTask.isCancelled {
                captureTask.cancel()
                await MainActor.run {
                    if self.isExtracting {
                        self.isExtracting = false
                        self.notification = "Capture timed out — try again"
                    }
                }
            }
        }
        await captureTask.value
    }

    private func _captureAndExtract() async {
        defer { Task { @MainActor in self.isExtracting = false } }

        do {
            let (image, appName) = try await ScreenCaptureEngine.captureFrontmostWindow()
            await showNotification("Captured \(appName) — Flaxie is reading...")

            let text = try await VisionOCR.extractText(from: image)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await showNotification("No text found on screen")
                return
            }

            let response = try await FlaxieAPIClient.shared.processNotes(
                rawNotes: text,
                meetingTitle: appName,
                source: ActionItemSource.screen.rawValue
            )
            guard !response.items.isEmpty else {
                await showNotification("No action items found in \(appName)")
                return
            }

            var savedItems: [ActionItem] = []
            for e in response.items {
                var item = ActionItem(
                    task: e.task,
                    source: .screen,
                    sourceDetail: appName,
                    deadline: e.deadline,
                    deadlineDate: e.deadline_date,
                    supabaseId: e.id
                )
                if let p = e.assigned_to {
                    item.assignedTo = Person(name: p.name, email: p.email, slackUserId: p.slack_user_id, isCurrentUser: p.is_current_user ?? false)
                }
                try DatabaseManager.shared.save(&item)
                NotificationManager.shared.scheduleDeadlineNotification(for: item)
                savedItems.append(item)
            }

            await MainActor.run { self.loadItems() }
            await showNotification("\(savedItems.count) action item\(savedItems.count == 1 ? "" : "s") from \(appName)")
            logActivity("Screen capture: \(savedItems.count) items from \(appName)")
        } catch ScreenCaptureError.capturePermissionDenied {
            if CGPreflightScreenCaptureAccess() {
                // Permission is granted but SCKit still failed — transient error
                await showNotification("Capture failed — please try again")
            } else {
                // Permission not yet active — DO NOT call CGRequestScreenCaptureAccess() here,
                // it opens System Settings on every click. Just tell the user what to do.
                await showNotification("Restart Flaxie after enabling screen recording in System Settings → Privacy")
            }
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
            await showNotification("Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Manual paste

    func processManualNotes(_ text: String, meetingTitle: String?) async {
        await processNotes(text: text, source: .manual, meetingTitle: meetingTitle, meetingDate: Date())
    }

    // MARK: - Status updates

    func updateStatus(itemId: Int64, status: ItemStatus) {
        guard let item = actionItems.first(where: { $0.id == itemId }) else { return }
        updateStatus(item, status: status)
    }

    func updateStatus(_ item: ActionItem, status: ItemStatus) {
        do {
            try DatabaseManager.shared.updateStatus(item, status: status)
            if status == .done {
                NotificationManager.shared.cancelDeadlineNotification(for: item)
                NotificationManager.shared.cancelNudge(for: item)
                logActivity("\(item.task) marked done")
            }
            loadItems()
            Task { try? await supabase.syncItem(item) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggle(_ item: ActionItem) {
        let newStatus: ItemStatus = item.status == .done ? .todo : .done
        updateStatus(item, status: newStatus)
    }

    func delete(_ item: ActionItem) {
        do {
            NotificationManager.shared.cancelDeadlineNotification(for: item)
            try DatabaseManager.shared.delete(item)
            loadItems()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Edit

    func updateItem(_ item: ActionItem, newTask: String, newDeadline: String?) {
        let newDeadlineDate = parseDeadlineDate(newDeadline)
        do {
            NotificationManager.shared.cancelDeadlineNotification(for: item)
            try DatabaseManager.shared.updateTask(item, newTask: newTask, newDeadline: newDeadline, newDeadlineDate: newDeadlineDate)
            var updated = item
            updated.deadlineDate = newDeadlineDate
            NotificationManager.shared.scheduleDeadlineNotification(for: updated)
            loadItems()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - AI Draft

    func draftWithFlaxie(item: ActionItem, type: AIDraftType) async {
        await showNotification("Flaxie is drafting...")
        do {
            let response = try await FlaxieAPIClient.shared.generateDraft(item: item, draftType: type.rawValue)
            try DatabaseManager.shared.updateAIDraft(item, draft: response.draft, type: type)
            loadItems()
            await showNotification("Draft ready — click to view")
            logActivity("Drafted \(type.rawValue) for: \(item.task)")
        } catch {
            await showNotification("Draft failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Gmail

    func syncGmailFromPopover() async {
        await showNotification("Syncing Gmail...")
        await pollGmail()
        if notification == "Syncing Gmail..." {
            await showNotification("Gmail synced — no new action items")
        }
    }

    func startGmailPolling() {
        let minutes = UserDefaults.standard.integer(forKey: "gmail_poll_minutes")
        let interval = TimeInterval(minutes == 0 ? 5 : minutes) * 60
        Task { await pollGmail() }
        gmailTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.pollGmail() }
        }
    }

    func pollGmail() async {
        guard gmail.isConnected else { return }
        do {
            let emails = try await gmail.fetchRecentEmails(hours: 24)
            guard !emails.isEmpty else { return }
            let myEmail = await gmail.getUserEmail()

            for email in emails {
                guard !isAutomatedEmail(from: email.from, subject: email.subject) else { continue }
                let replyText = await gmail.fetchThreadReply(threadId: email.threadId, afterMessageId: email.id, userEmail: myEmail)
                let content = "Subject: \(email.subject)\nFrom: \(email.from)\n\n\(email.body)"
                let replyContext: String
                if let reply = replyText {
                    replyContext = "I replied with: \"\(reply)\". Determine if my reply fully resolves the action item, or if I deferred it — in which case it is still outstanding."
                } else {
                    replyContext = "I have NOT replied yet, so any action requested is still outstanding."
                }
                let context = """
                    Email to me from \(email.from). Subject: "\(email.subject)". \
                    \(replyContext) Extract ONLY clear action items where someone is explicitly asking ME \
                    to do something, or where I made a commitment. Ignore newsletters, receipts, \
                    automated notifications, and anything that doesn't require a specific action from me.
                    """
                let gmailContent = "Context: \(context)\n\nText:\n\(content)"
                let emailResponse = try await FlaxieAPIClient.shared.processNotes(
                    rawNotes: gmailContent,
                    meetingTitle: email.subject,
                    source: ActionItemSource.gmail.rawValue
                )
                for e in emailResponse.items {
                    var item = ActionItem(
                        task: e.task,
                        source: .gmail,
                        sourceDetail: "From: \(email.from) — \(email.subject)",
                        deadline: e.deadline,
                        deadlineDate: e.deadline_date,
                        supabaseId: e.id
                    )
                    try DatabaseManager.shared.save(&item)
                    NotificationManager.shared.scheduleDeadlineNotification(for: item)
                }
            }
            await MainActor.run { self.loadItems() }
        } catch {
            print("Gmail poll error: \(error)")
        }
    }

    private func isAutomatedEmail(from: String, subject: String) -> Bool {
        let fromLower = from.lowercased()
        let subjectLower = subject.lowercased()
        let fromPatterns = ["no-reply", "noreply", "do-not-reply", "notifications@", "alert@", "newsletter@",
                            "mailer@", "support@", "billing@", "shipping@", "linkedin.com", "github.com",
                            "sendgrid.net", "mailchimp.com"]
        let subjectPatterns = ["unsubscribe", "invoice #", "order confirmation", "your shipment",
                               "password reset", "verify your", "weekly digest", "% off", "sale ends"]
        for p in fromPatterns where fromLower.contains(p) { return true }
        for p in subjectPatterns where subjectLower.contains(p) { return true }
        return false
    }

    // MARK: - Slack notifications for delegated items

    private func notifyDelegatedViaSlack(_ items: [ActionItem]) async {
        guard slack.isConnected else { return }
        for item in items {
            guard let assignee = item.assignedTo, !assignee.isCurrentUser else { continue }
            do {
                try await slack.sendNudge(to: assignee, for: item)
                logActivity("Flaxie notified \(assignee.name) via Slack")
            } catch {
                print("[AppState] Slack notify failed for \(assignee.name): \(error)")
            }
        }
    }

    // MARK: - Person resolution

    func resolveOrCreatePerson(named name: String?) -> Person? {
        guard let name, !name.isEmpty else { return nil }

        // Check if it's the current user
        let nameLower = name.lowercased()
        if !currentUser.name.isEmpty && currentUser.name.lowercased().contains(nameLower) {
            return currentUser
        }

        // Check Slack workspace members
        if let match = slack.workspaceMembers.first(where: { $0.name.lowercased().contains(nameLower) }) {
            return match
        }

        // Create a new person
        return Person(name: name, isCurrentUser: false)
    }

    // MARK: - Helpers

    private func buildContext(source: ActionItemSource, meetingTitle: String?) -> String {
        var parts = ["Source: \(source.displayName)"]
        if let title = meetingTitle { parts.append("Meeting: \(title)") }
        if !currentUser.name.isEmpty { parts.append("Current user: \(currentUser.name)") }
        return parts.joined(separator: ". ")
    }

    private func saveAndSchedule(_ items: [ActionItem]) throws {
        for var item in items {
            try DatabaseManager.shared.save(&item)
            NotificationManager.shared.scheduleDeadlineNotification(for: item)
        }
    }

    func parseDeadlineDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        func defaultToMorning(_ date: Date) -> Date {
            let c = cal.dateComponents([.hour, .minute], from: date)
            if c.hour == 0 && c.minute == 0 {
                return cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            }
            return date
        }

        if lower.contains("end of day") || lower.contains("eod") || lower.contains("cob") {
            return cal.date(bySettingHour: 17, minute: 0, second: 0, of: Date())
        }
        if lower == "today" || lower.hasSuffix("today") {
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)
        }
        if lower.contains("tomorrow") {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
            if let detected = detectDate(in: text), !isMidnight(detected, cal: cal) { return detected }
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
        if let date = detectDate(in: text) { return defaultToMorning(date) }
        return nil
    }

    private func detectDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        return detector.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text))?.date
    }

    private func isMidnight(_ date: Date, cal: Calendar) -> Bool {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return c.hour == 0 && c.minute == 0
    }

    @MainActor
    func showNotification(_ message: String) async {
        notification = message
        let duration: Double = message.lowercased().hasPrefix("error") ? 8 : 3
        Task {
            try? await Task.sleep(for: .seconds(duration))
            if notification == message { notification = nil }
        }
    }

    func logActivity(_ message: String) {
        DispatchQueue.main.async {
            self.activityLog.insert((Date(), message), at: 0)
            if self.activityLog.count > 50 { self.activityLog = Array(self.activityLog.prefix(50)) }
        }
    }
}
