import Foundation
import UserNotifications
import AppKit

extension Notification.Name {
    static let openDashboard       = Notification.Name("com.hari.actionitems.openDashboard")
    static let nudgeResponseDone   = Notification.Name("com.hari.actionitems.nudgeResponseDone")
    static let nudgeResponseSend   = Notification.Name("com.hari.actionitems.nudgeResponseSend")
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
        // Deadline reminder — my own tasks
        let openAction = UNNotificationAction(identifier: "OPEN_DASHBOARD", title: "Open", options: [.foreground])
        let doneAction = UNNotificationAction(identifier: "MARK_DONE", title: "Done ✓", options: [])
        let deadlineCategory = UNNotificationCategory(
            identifier: "DEADLINE_REMINDER",
            actions: [doneAction, openAction],
            intentIdentifiers: [],
            options: []
        )

        // Nudge for delegated task — ask manager if they want to send
        let sendNudgeAction = UNNotificationAction(identifier: "SEND_NUDGE", title: "Send Nudge", options: [])
        let skipNudgeAction = UNNotificationAction(identifier: "SKIP_NUDGE", title: "Skip", options: [])
        let delegateNudgeCategory = UNNotificationCategory(
            identifier: "DELEGATE_NUDGE",
            actions: [sendNudgeAction, skipNudgeAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([deadlineCategory, delegateNudgeCategory])
    }

    // MARK: - Deadline Notifications (my tasks)

    func scheduleDeadlineNotification(for item: ActionItem) {
        guard let deadlineDate = item.deadlineDate, let itemId = item.id else { return }
        let fireDate = deadlineDate.addingTimeInterval(-30 * 60)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Action Item Due in 30 Minutes"
        content.body = item.task
        content.sound = .default
        content.categoryIdentifier = "DEADLINE_REMINDER"
        content.userInfo = ["itemId": itemId]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "deadline_\(itemId)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelDeadlineNotification(for item: ActionItem) {
        guard let id = item.id else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["deadline_\(id)"])
    }

    // MARK: - Self Nudge (my tasks overdue)

    func scheduleNudge(for item: ActionItem) {
        guard let itemId = item.id else { return }

        let content = UNMutableNotificationContent()
        content.title = "Flaxie Reminder"
        content.body = item.task
        if let deadline = item.deadlineDisplayText {
            content.subtitle = "Due: \(deadline)"
        }
        content.sound = .default
        content.categoryIdentifier = "DEADLINE_REMINDER"
        content.userInfo = ["itemId": itemId, "nudge": true]

        // Fire immediately (5 seconds delay to avoid instant popup during app logic)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "nudge_\(itemId)_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelNudge(for item: ActionItem) {
        guard let id = item.id else { return }
        // We can't easily cancel nudges by prefix; just remove pending deadline ones
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nudge_\(id)"])
    }

    // MARK: - Delegate Nudge (ask manager before nudging teammate)

    func scheduleDelegateNudgePrompt(for item: ActionItem, assigneeName: String) {
        guard let itemId = item.id else { return }

        let content = UNMutableNotificationContent()
        content.title = "Flaxie: \(assigneeName) hasn't updated yet"
        content.body = item.task
        content.subtitle = "Want me to send them a nudge?"
        content.sound = .default
        content.categoryIdentifier = "DELEGATE_NUDGE"
        content.userInfo = ["itemId": itemId, "assigneeName": assigneeName]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "delegate_nudge_\(itemId)_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Meeting Notifications (calendar-based, no recording — just awareness)

    func scheduleMeetingPrompt(title: String, startDate: Date, eventId: String) {
        let fireDate = max(startDate.addingTimeInterval(-60), Date().addingTimeInterval(3))
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Meeting Starting Soon"
        content.body = "\(title) — Flaxie is ready to capture action items"
        content.sound = .default
        content.categoryIdentifier = "DEADLINE_REMINDER"
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
        let userInfo = response.notification.request.content.userInfo
        let itemId = userInfo["itemId"] as? Int64

        switch response.actionIdentifier {
        case "MARK_DONE":
            if let id = itemId {
                NotificationCenter.default.post(name: .nudgeResponseDone, object: nil, userInfo: ["itemId": id])
            }
        case "SEND_NUDGE":
            if let id = itemId {
                NotificationCenter.default.post(name: .nudgeResponseSend, object: nil, userInfo: ["itemId": id])
            }
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
