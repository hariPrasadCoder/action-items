import Foundation
import SwiftUI

class AppState: ObservableObject {
    // MARK: - Published state

    @Published var actionItems: [ActionItem] = []
    @Published var isRecordingMeeting = false
    @Published var isMeetingModelLoading = false
    @Published var liveTranscript = ""
    @Published var isExtracting = false
    @Published var lastError: String?
    @Published var notification: String?

    // MARK: - Services

    let gmail = GmailService()
    let calendar = CalendarService.shared

    private var audioEngine = AudioEngine()
    private var transcriptionEngine = TranscriptionEngine()
    private var gmailTimer: Timer?

    // MARK: - Init

    init() {
        loadItems()
    }

    // MARK: - Data

    func loadItems() {
        do {
            actionItems = try DatabaseManager.shared.fetchAll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggle(_ item: ActionItem) {
        do {
            try DatabaseManager.shared.toggleCompleted(item)
            // Cancel deadline notification if completing
            if !item.isCompleted {
                NotificationManager.shared.cancelDeadlineNotification(for: item)
            }
            loadItems()
        } catch {
            lastError = error.localizedDescription
        }
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

    // MARK: - Screen Capture

    func captureScreenAndExtract() async {
        guard !isExtracting else { return }
        await MainActor.run { isExtracting = true }
        defer { Task { @MainActor in self.isExtracting = false } }

        do {
            let (image, appName) = try await ScreenCaptureEngine.captureFrontmostWindow()
            await showNotification("Captured \(appName) — extracting...")

            let text = try await VisionOCR.extractText(from: image)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await showNotification("No text found on screen")
                return
            }

            let extracted = try await KimiService.extractActionItems(
                from: text,
                context: "This text was captured from \(appName), a messaging/communication app. The user is the recipient/viewer of this conversation. Extract only action items clearly directed at the user or explicitly assigned to someone by name."
            )

            guard !extracted.isEmpty else {
                await showNotification("No action items found in \(appName)")
                return
            }

            let items = extracted.map { e in
                ActionItem(task: e.task, source: .screen, sourceDetail: appName,
                           deadline: e.deadline, deadlineDate: parseDeadlineDate(e.deadline))
            }
            try saveAndSchedule(items)

            await MainActor.run { self.loadItems() }
            await showNotification("\(extracted.count) action item\(extracted.count == 1 ? "" : "s") from \(appName)")
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
            await showNotification("Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Meeting Recording

    func toggleMeetingRecording() async {
        if isRecordingMeeting {
            await stopMeetingRecording()
        } else {
            await startMeetingRecording()
        }
    }

    private func startMeetingRecording() async {
        await MainActor.run {
            self.isMeetingModelLoading = true
            self.liveTranscript = ""
        }
        await showNotification("Loading Whisper model...")

        do {
            let modelSize = UserDefaults.standard.string(forKey: "whisper_model") ?? "base"
            try await transcriptionEngine.prepare(modelSize: modelSize)
            await MainActor.run { self.isMeetingModelLoading = false }

            audioEngine.onAudioChunkReady = { [weak self] url in
                Task { await self?.processAudioChunk(url) }
            }
            transcriptionEngine.onTranscriptUpdate = { [weak self] text in
                Task { @MainActor [weak self] in self?.liveTranscript += " " + text }
            }

            _ = try audioEngine.startRecording()
            await MainActor.run { self.isRecordingMeeting = true }
            await showNotification("Meeting recording started — press \u{2318}\u{21E7}M to stop")
        } catch {
            await MainActor.run {
                self.isMeetingModelLoading = false
                self.lastError = error.localizedDescription
            }
            await showNotification("Failed to start: \(error.localizedDescription)")
        }
    }

    private func stopMeetingRecording() async {
        let finalChunkURL = audioEngine.stopRecording()
        await MainActor.run { self.isRecordingMeeting = false }

        if let url = finalChunkURL {
            await processAudioChunk(url)
        }

        let transcript = transcriptionEngine.completeTranscript
        transcriptionEngine.release()

        guard !transcript.isEmpty else {
            await showNotification("No transcript recorded")
            return
        }

        await MainActor.run { self.isExtracting = true }
        await showNotification("Extracting action items from meeting...")

        do {
            let meetingDate = Date().formatted(date: .abbreviated, time: .shortened)
            let extracted = try await KimiService.extractActionItems(
                from: transcript,
                context: "Meeting transcript from \(meetingDate)"
            )
            let items = extracted.map {
                ActionItem(task: $0.task, source: .meeting,
                           sourceDetail: "Meeting \(meetingDate)",
                           deadline: $0.deadline, deadlineDate: parseDeadlineDate($0.deadline))
            }
            try saveAndSchedule(items)
            await MainActor.run { self.loadItems() }
            await showNotification("\(extracted.count) action item\(extracted.count == 1 ? "" : "s") from meeting")
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
        }
        await MainActor.run { self.isExtracting = false }
    }

    private func processAudioChunk(_ url: URL) async {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("[Transcription] Processing chunk: \(url.lastPathComponent), size: \(fileSize) bytes")

        guard fileSize > 4096 else {
            print("[Transcription] Skipping — audio file too small (\(fileSize) bytes), mic may not be capturing")
            await showNotification("No audio captured — check microphone permission in System Settings")
            return
        }

        do {
            let text = try await transcriptionEngine.transcribeChunk(at: url)
            print("[Transcription] Result: '\(text.isEmpty ? "(empty)" : text)'")
            try? FileManager.default.removeItem(at: url)
        } catch {
            print("[Transcription] Error: \(error)")
            await showNotification("Transcription error: \(error.localizedDescription)")
        }
    }

    // MARK: - Gmail Sync from Popover

    func syncGmailFromPopover() async {
        await showNotification("Syncing Gmail...")
        await pollGmail()
        // If no notification was set by pollGmail, confirm completion
        if notification == "Syncing Gmail..." {
            await showNotification("Gmail synced — no new action items")
        }
    }

    // MARK: - Edit Items

    func updateItem(_ item: ActionItem, newTask: String, newDeadline: String?) {
        let newDeadlineDate = parseDeadlineDate(newDeadline)
        do {
            NotificationManager.shared.cancelDeadlineNotification(for: item)
            try DatabaseManager.shared.updateTask(item, newTask: newTask, newDeadline: newDeadline, newDeadlineDate: newDeadlineDate)
            // Reschedule with new deadline
            if let id = item.id {
                var updated = item
                updated.deadlineDate = newDeadlineDate
                NotificationManager.shared.scheduleDeadlineNotification(for: updated)
            }
            loadItems()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Gmail Polling

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

                let replyText = await gmail.fetchThreadReply(
                    threadId: email.threadId,
                    afterMessageId: email.id,
                    userEmail: myEmail
                )

                let content = "Subject: \(email.subject)\nFrom: \(email.from)\n\n\(email.body)"
                let replyContext: String
                if let reply = replyText {
                    replyContext = "I replied to this email with: \"\(reply)\". Determine if my reply fully resolves the action item, or if I deferred it (e.g. 'I'll do it later', 'will send soon') — in which case it is still an outstanding action item."
                } else {
                    replyContext = "I have NOT replied to this email yet, so any action requested is still outstanding."
                }

                let context = """
                    This is an email sent directly to me from \(email.from). \
                    Subject: "\(email.subject)". \
                    \(replyContext) \
                    Extract ONLY clear action items where someone is explicitly asking ME to do something, \
                    or where I made a commitment to do something. \
                    Ignore newsletters, promotions, receipts, shipping updates, automated notifications, \
                    and anything that doesn't require a specific action from me personally.
                    """
                let extracted = try await KimiService.extractActionItems(from: content, context: context)
                let items = extracted.map {
                    ActionItem(task: $0.task, source: .gmail,
                               sourceDetail: "From: \(email.from) — \(email.subject)",
                               deadline: $0.deadline, deadlineDate: parseDeadlineDate($0.deadline))
                }
                try saveAndSchedule(items)
            }
            await MainActor.run { self.loadItems() }
        } catch {
            print("Gmail poll error: \(error)")
        }
    }

    /// Returns true if the email is automated/promotional and should be skipped.
    private func isAutomatedEmail(from: String, subject: String) -> Bool {
        let fromLower = from.lowercased()
        let subjectLower = subject.lowercased()

        let automatedFromPatterns = [
            "no-reply", "noreply", "do-not-reply", "donotreply",
            "notifications@", "notification@", "alert@", "alerts@",
            "newsletter@", "news@", "updates@", "update@",
            "mailer@", "mailer-daemon", "postmaster@",
            "support@", "hello@", "info@", "team@", "contact@",
            "marketing@", "promo@", "offers@", "deals@",
            "billing@", "invoice@", "receipts@", "orders@",
            "shipping@", "delivery@", "track@",
            "linkedin.com", "twitter.com", "facebook.com", "instagram.com",
            "github.com", "slack.com", "notion.so", "trello.com",
            "amazonaws.com", "sendgrid.net", "mailchimp.com", "klaviyo.com"
        ]

        let automatedSubjectPatterns = [
            "unsubscribe", "opt out", "opt-out",
            "invoice #", "order #", "order confirmation", "receipt for",
            "your order", "your shipment", "has shipped", "out for delivery",
            "password reset", "verify your", "confirm your email",
            "security alert", "sign-in attempt", "login attempt",
            "weekly digest", "daily digest", "monthly newsletter",
            "% off", "sale ends", "limited time", "exclusive offer",
            "you've been invited", "wants to connect", "sent you a message"
        ]

        for pattern in automatedFromPatterns where fromLower.contains(pattern) { return true }
        for pattern in automatedSubjectPatterns where subjectLower.contains(pattern) { return true }
        return false
    }

    // MARK: - Helpers

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

        // Helper: if a parsed date has no explicit time (midnight), default it to 9am
        func defaultToMorning(_ date: Date) -> Date {
            let components = cal.dateComponents([.hour, .minute], from: date)
            // If time is midnight (00:00), treat it as date-only → set to 9am
            if components.hour == 0 && components.minute == 0 {
                return cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            }
            return date
        }

        // Special keyword parsing
        if lower.contains("end of day") || lower.contains("eod") || lower.contains("cob") {
            return cal.date(bySettingHour: 17, minute: 0, second: 0, of: Date())
        }
        if lower == "today" || lower.hasSuffix("today") {
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)
        }
        if lower.contains("tomorrow") {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
            // Check if a time was specified alongside "tomorrow"
            if let detected = detectDate(in: text), !isMidnight(detected, cal: cal) {
                return detected
            }
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }

        // NSDataDetector handles "next Friday", "March 20", "3pm", "in 2 hours", etc.
        if let date = detectDate(in: text) {
            return defaultToMorning(date)
        }
        return nil
    }

    private func detectDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.date
    }

    private func isMidnight(_ date: Date, cal: Calendar) -> Bool {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return c.hour == 0 && c.minute == 0
    }

    @MainActor
    private func showNotification(_ message: String) async {
        notification = message
        let duration: Double = message.lowercased().hasPrefix("error") ? 8 : 3
        Task {
            try? await Task.sleep(for: .seconds(duration))
            if notification == message { notification = nil }
        }
    }

    var pendingCount: Int { actionItems.filter { !$0.isCompleted }.count }
    var overdueCount: Int { actionItems.filter { !$0.isCompleted && $0.urgency == .overdue }.count }
}
