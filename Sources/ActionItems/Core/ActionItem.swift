import Foundation
import GRDB
import SwiftUI

enum ActionItemSource: String, Codable, CaseIterable {
    case meeting = "meeting"
    case screen = "screen"
    case gmail = "gmail"

    var displayName: String {
        switch self {
        case .meeting: return "Meeting"
        case .screen: return "Screen"
        case .gmail: return "Gmail"
        }
    }

    var icon: String {
        switch self {
        case .meeting: return "waveform.circle"
        case .screen: return "camera.viewfinder"
        case .gmail: return "envelope"
        }
    }

    var color: Color {
        switch self {
        case .meeting: return .blue
        case .screen: return .indigo
        case .gmail: return .orange
        }
    }
}

enum DeadlineUrgency {
    case none, overdue, today, soon, future

    var color: Color {
        switch self {
        case .none:    return .secondary
        case .overdue: return .red
        case .today:   return .orange
        case .soon:    return Color(red: 0.8, green: 0.6, blue: 0.0) // amber
        case .future:  return .teal
        }
    }

    var icon: String {
        switch self {
        case .none:    return ""
        case .overdue: return "exclamationmark.triangle.fill"
        case .today:   return "clock.fill"
        case .soon:    return "clock"
        case .future:  return "calendar"
        }
    }
}

struct ActionItem: Identifiable, Codable, Equatable {
    var id: Int64?
    var task: String
    var source: ActionItemSource
    var sourceDetail: String   // e.g. "Slack", "Meeting with John", "From: alice@example.com"
    var isCompleted: Bool
    var createdAt: Date
    var deadline: String?      // free-text deadline if mentioned
    var deadlineDate: Date?    // parsed deadline for notifications and urgency

    init(
        id: Int64? = nil,
        task: String,
        source: ActionItemSource,
        sourceDetail: String = "",
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        deadline: String? = nil,
        deadlineDate: Date? = nil
    ) {
        self.id = id
        self.task = task
        self.source = source
        self.sourceDetail = sourceDetail
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.deadline = deadline
        self.deadlineDate = deadlineDate
    }

    // MARK: - Computed

    var urgency: DeadlineUrgency {
        guard let date = deadlineDate else { return .none }
        let now = Date()
        if date < now { return .overdue }
        let hours = date.timeIntervalSince(now) / 3600
        if hours < 24 { return .today }
        if hours < 72 { return .soon }
        return .future
    }

    var deadlineDisplayText: String? {
        guard let date = deadlineDate else { return deadline }
        let now = Date()
        if date < now {
            return "Overdue"
        }
        let hours = date.timeIntervalSince(now) / 3600
        if hours < 24 {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

// GRDB conformance
extension ActionItem: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "action_items"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let task = Column(CodingKeys.task)
        static let source = Column(CodingKeys.source)
        static let sourceDetail = Column(CodingKeys.sourceDetail)
        static let isCompleted = Column(CodingKeys.isCompleted)
        static let createdAt = Column(CodingKeys.createdAt)
        static let deadline = Column(CodingKeys.deadline)
        static let deadlineDate = Column(CodingKeys.deadlineDate)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// Decoded from Claude API response
struct ExtractedActionItem: Codable {
    let task: String
    let deadline: String?

    enum CodingKeys: String, CodingKey {
        case task
        case deadline
    }
}
