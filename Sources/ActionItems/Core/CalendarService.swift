import Foundation
import EventKit

class CalendarService: ObservableObject {
    static let shared = CalendarService()

    private let store = EKEventStore()
    @Published var isAuthorized = false
    @Published var upcomingMeetings: [EKEvent] = []

    private var scheduledEventIds: Set<String> = []
    private var checkTimer: Timer?

    private init() {
        isAuthorized = hasAccess
        if isAuthorized {
            startMonitoring()
        }
    }

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            await MainActor.run { self.isAuthorized = granted }
            if granted {
                startMonitoring()
            }
        } catch {
            print("[Calendar] Access error: \(error)")
        }
    }

    func startMonitoring() {
        refreshUpcomingMeetings()
        checkUpcomingMeetingsForNotifications()
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshUpcomingMeetings()
            self?.checkUpcomingMeetingsForNotifications()
        }
    }

    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    func refreshUpcomingMeetings() {
        guard hasAccess else { return }
        let meetings = fetchUpcomingMeetings(hours: 8)
        DispatchQueue.main.async { self.upcomingMeetings = meetings }
    }

    private func checkUpcomingMeetingsForNotifications() {
        guard hasAccess else { return }
        let now = Date()
        let lookAhead = now.addingTimeInterval(2 * 60) // Next 2 minutes

        let predicate = store.predicateForEvents(withStart: now, end: lookAhead, calendars: nil)
        let events = store.events(matching: predicate)

        for event in events {
            guard !event.isAllDay,
                  !scheduledEventIds.contains(event.eventIdentifier) else { continue }

            // Only notify for meetings with attendees or video call links
            let hasAttendees = (event.attendees?.count ?? 0) > 1
            let notes = (event.notes ?? "").lowercased()
            let location = (event.location ?? "").lowercased()
            let isVideoCall = notes.contains("zoom") || notes.contains("meet.google") ||
                              notes.contains("teams") || notes.contains("webex") ||
                              location.contains("zoom") || location.contains("meet.google")

            guard hasAttendees || isVideoCall else { continue }

            scheduledEventIds.insert(event.eventIdentifier)
            NotificationManager.shared.scheduleMeetingPrompt(
                title: event.title ?? "Meeting",
                startDate: event.startDate,
                eventId: event.eventIdentifier
            )
        }
    }

    func fetchUpcomingMeetings(hours: Int = 8) -> [EKEvent] {
        guard hasAccess else { return [] }
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(hours) * 3600)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }
}
