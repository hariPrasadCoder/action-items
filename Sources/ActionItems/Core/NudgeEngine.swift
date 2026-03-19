import Foundation

/// Flaxie's nudge brain — runs every 15 minutes, decides who needs a push and how.
///
/// Rules:
/// - Never nudge between 7pm (19:00) and 9am (09:00)
/// - Never nudge if the item was updated in the last 6 hours
/// - Never nudge if status is done or blocked
/// - For MY tasks: fire macOS notification directly
/// - For DELEGATED tasks: ask the manager first via macOS notification,
///   then if approved, send a Slack DM via SlackService
class NudgeEngine {
    @Published var isRunning = false

    weak var appState: AppState?
    weak var slackService: SlackService?

    private var timer: Timer?

    // MARK: - Lifecycle

    func start(appState: AppState, slackService: SlackService) {
        self.appState = appState
        self.slackService = slackService
        isRunning = true

        // Check every 15 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            self?.runNudgeCycle()
        }

        // Listen for user responses from notification actions
        setupNotificationObservers()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    // MARK: - Nudge cycle

    private func runNudgeCycle() {
        // Respect quiet hours (7pm – 9am)
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 9 && hour < 19 else { return }

        guard let pendingItems = try? DatabaseManager.shared.fetchPendingForNudge() else { return }

        for item in pendingItems {
            let isMyTask = item.assignedTo == nil || (item.assignedTo?.isCurrentUser ?? false)

            if isMyTask {
                nudgeSelf(for: item)
            } else if let assignee = item.assignedTo {
                nudgeDelegate(for: item, assignee: assignee)
            }
        }
    }

    // MARK: - Self nudge (my overdue tasks)

    private func nudgeSelf(for item: ActionItem) {
        // Only nudge if overdue or due today
        guard item.urgency == .overdue || item.urgency == .today else { return }

        NotificationManager.shared.scheduleNudge(for: item)
        recordNudge(item)
    }

    // MARK: - Delegate nudge (ask manager first)

    private func nudgeDelegate(for item: ActionItem, assignee: Person) {
        // Only nudge delegated tasks if overdue
        guard item.urgency == .overdue else { return }

        NotificationManager.shared.scheduleDelegateNudgePrompt(for: item, assigneeName: assignee.name)
        recordNudge(item)
    }

    // MARK: - Send actual Slack nudge (called after manager approves)

    func sendSlackNudge(for itemId: Int64) {
        guard let items = try? DatabaseManager.shared.fetchPending(),
              let item = items.first(where: { $0.id == itemId }),
              let assignee = item.assignedTo,
              let slack = slackService else { return }

        Task {
            do {
                try await slack.sendNudge(to: assignee, for: item)
                print("[NudgeEngine] Sent Slack nudge to \(assignee.name) for: \(item.task)")
            } catch {
                print("[NudgeEngine] Slack nudge failed: \(error)")
            }
        }
    }

    // MARK: - Record nudge in DB

    private func recordNudge(_ item: ActionItem) {
        try? DatabaseManager.shared.updateNudgeTracking(item)
    }

    // MARK: - Notification observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .nudgeResponseDone,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let itemId = notification.userInfo?["itemId"] as? Int64 {
                self?.appState?.updateStatus(itemId: itemId, status: .done)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .nudgeResponseSend,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let itemId = notification.userInfo?["itemId"] as? Int64 {
                self?.sendSlackNudge(for: itemId)
            }
        }
    }
}
