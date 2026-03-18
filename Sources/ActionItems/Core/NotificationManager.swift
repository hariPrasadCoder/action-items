import Foundation
import UserNotifications
import AppKit

extension Notification.Name {
    static let startMeetingRecording = Notification.Name("com.hari.actionitems.startMeetingRecording")
    static let openDashboard = Notification.Name("com.hari.actionitems.openDashboard")
}

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupCategories()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { print("[Notifications] Auth error: \(error)") }
            else { print("[Notifications] Granted: \(granted)") }
        }
    }

    private func setupCategories() {
        let recordAction = UNNotificationAction(identifier: "RECORD", title: "Record Meeting", options: [.foreground])
        let skipAction = UNNotificationAction(identifier: "SKIP", title: "Skip", options: [])
        let meetingCategory = UNNotificationCategory(
            identifier: "MEETING_PROMPT",
            actions: [recordAction, skipAction],
            intentIdentifiers: [],
            options: []
        )

        let openAction = UNNotificationAction(identifier: "OPEN_DASHBOARD", title: "Open", options: [.foreground])
        let deadlineCategory = UNNotificationCategory(
            identifier: "DEADLINE_REMINDER",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([meetingCategory, deadlineCategory])
    }

    // MARK: - Deadline Notifications

    func scheduleDeadlineNotification(for item: ActionItem) {
        guard let deadlineDate = item.deadlineDate, let itemId = item.id else { return }
        let fireDate = deadlineDate.addingTimeInterval(-30 * 60)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Action Item Due in 30 Minutes"
        content.body = item.task
        content.sound = .default
        content.categoryIdentifier = "DEADLINE_REMINDER"

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "deadline_\(itemId)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelDeadlineNotification(for item: ActionItem) {
        guard let id = item.id else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["deadline_\(id)"])
    }

    // MARK: - Meeting Notifications

    func scheduleMeetingPrompt(title: String, startDate: Date, eventId: String) {
        // Notify 1 minute before (or at start if < 1 minute away)
        let fireDate = max(startDate.addingTimeInterval(-60), Date().addingTimeInterval(3))
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Meeting Starting Soon"
        content.body = "\(title) — Record this meeting?"
        content.sound = .default
        content.categoryIdentifier = "MEETING_PROMPT"
        content.userInfo = ["meetingTitle": title]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "meeting_\(eventId)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelMeetingPrompt(eventId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["meeting_\(eventId)"])
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "RECORD":
            NotificationCenter.default.post(name: .startMeetingRecording, object: nil)
        case "OPEN_DASHBOARD", UNNotificationDefaultActionIdentifier:
            NotificationCenter.default.post(name: .openDashboard, object: nil)
        default:
            break
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
