import Foundation
import GRDB
import SwiftUI

// MARK: - Person

struct Person: Codable, Equatable, Hashable {
    var name: String
    var email: String?
    var slackUserId: String?
    var isCurrentUser: Bool

    init(name: String, email: String? = nil, slackUserId: String? = nil, isCurrentUser: Bool = false) {
        self.name = name
        self.email = email
        self.slackUserId = slackUserId
        self.isCurrentUser = isCurrentUser
    }
}

// MARK: - ItemStatus

enum ItemStatus: String, Codable, CaseIterable {
    case todo       = "todo"
    case inprogress = "inprogress"
    case done       = "done"
    case blocked    = "blocked"

    var displayName: String {
        switch self {
        case .todo:       return "To Do"
        case .inprogress: return "In Progress"
        case .done:       return "Done"
        case .blocked:    return "Blocked"
        }
    }

    var icon: String {
        switch self {
        case .todo:       return "circle"
        case .inprogress: return "arrow.triangle.2.circlepath"
        case .done:       return "checkmark.circle.fill"
        case .blocked:    return "exclamationmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .todo:       return Color(red: 0.55, green: 0.55, blue: 0.60)
        case .inprogress: return Color(red: 0.20, green: 0.50, blue: 0.90)
        case .done:       return Color(red: 0.20, green: 0.75, blue: 0.45)
        case .blocked:    return Color(red: 0.90, green: 0.25, blue: 0.25)
        }
    }
}

// MARK: - AIDraftType

enum AIDraftType: String, Codable {
    case email = "email"
    case slack = "slack"
}

// MARK: - ActionItemSource

enum ActionItemSource: String, Codable, CaseIterable {
    case granola  = "granola"
    case fireflies = "fireflies"
    case otter    = "otter"
    case screen   = "screen"
    case gmail    = "gmail"
    case slack    = "slack"
    case manual   = "manual"
    case meeting  = "meeting"   // legacy — kept for existing data

    var displayName: String {
        switch self {
        case .granola:   return "Granola"
        case .fireflies: return "Fireflies"
        case .otter:     return "Otter"
        case .screen:    return "Screen"
        case .gmail:     return "Gmail"
        case .slack:     return "Slack"
        case .manual:    return "Manual"
        case .meeting:   return "Meeting"
        }
    }

    var icon: String {
        switch self {
        case .granola:   return "note.text"
        case .fireflies: return "waveform.circle"
        case .otter:     return "waveform"
        case .screen:    return "camera.viewfinder"
        case .gmail:     return "envelope"
        case .slack:     return "message"
        case .manual:    return "square.and.pencil"
        case .meeting:   return "waveform.circle"
        }
    }

    var color: Color {
        switch self {
        case .granola:   return Color(red: 0.353, green: 0.325, blue: 0.882) // flax purple
        case .fireflies: return Color(red: 0.90, green: 0.40, blue: 0.10)
        case .otter:     return Color(red: 0.20, green: 0.60, blue: 0.90)
        case .screen:    return .indigo
        case .gmail:     return .orange
        case .slack:     return Color(red: 0.44, green: 0.16, blue: 0.58)
        case .manual:    return Color(red: 0.40, green: 0.40, blue: 0.45)
        case .meeting:   return .blue
        }
    }
}

// MARK: - DeadlineUrgency

enum DeadlineUrgency {
    case none, overdue, today, soon, future

    var color: Color {
        switch self {
        case .none:    return .secondary
        case .overdue: return .red
        case .today:   return .orange
        case .soon:    return Color(red: 0.8, green: 0.6, blue: 0.0)
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

// MARK: - ActionItem

struct ActionItem: Identifiable, Equatable {
    var id: Int64?
    var task: String
    var source: ActionItemSource
    var sourceDetail: String
    var status: ItemStatus
    var createdAt: Date
    var deadline: String?
    var deadlineDate: Date?

    // People intelligence
    var assignedToJson: String?    // JSON-encoded Person
    var assignedByJson: String?    // JSON-encoded Person
    var participantsJson: String?  // JSON-encoded [Person]

    // Meeting context
    var meetingTitle: String?
    var meetingDate: Date?

    // AI actions
    var aiDraft: String?
    var aiDraftType: String?       // AIDraftType.rawValue

    // Collaboration
    var slackThreadId: String?
    var nudgeCount: Int
    var lastNudgedAt: Date?
    var supabaseId: String?

    // MARK: Computed: People

    var assignedTo: Person? {
        get {
            guard let json = assignedToJson, let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Person.self, from: data)
        }
        set {
            if let person = newValue, let data = try? JSONEncoder().encode(person) {
                assignedToJson = String(data: data, encoding: .utf8)
            } else {
                assignedToJson = nil
            }
        }
    }

    var assignedBy: Person? {
        get {
            guard let json = assignedByJson, let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Person.self, from: data)
        }
        set {
            if let person = newValue, let data = try? JSONEncoder().encode(person) {
                assignedByJson = String(data: data, encoding: .utf8)
            } else {
                assignedByJson = nil
            }
        }
    }

    var participants: [Person] {
        get {
            guard let json = participantsJson, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([Person].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                participantsJson = String(data: data, encoding: .utf8)
            } else {
                participantsJson = nil
            }
        }
    }

    // MARK: Computed: backward compat

    var isCompleted: Bool { status == .done }

    // MARK: Computed: Urgency

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
        if date < now { return "Overdue" }
        let hours = date.timeIntervalSince(now) / 3600
        if hours < 24 { return date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - Init

    init(
        id: Int64? = nil,
        task: String,
        source: ActionItemSource,
        sourceDetail: String = "",
        status: ItemStatus = .todo,
        createdAt: Date = Date(),
        deadline: String? = nil,
        deadlineDate: Date? = nil,
        assignedToJson: String? = nil,
        assignedByJson: String? = nil,
        participantsJson: String? = nil,
        meetingTitle: String? = nil,
        meetingDate: Date? = nil,
        aiDraft: String? = nil,
        aiDraftType: String? = nil,
        slackThreadId: String? = nil,
        nudgeCount: Int = 0,
        lastNudgedAt: Date? = nil,
        supabaseId: String? = nil
    ) {
        self.id = id
        self.task = task
        self.source = source
        self.sourceDetail = sourceDetail
        self.status = status
        self.createdAt = createdAt
        self.deadline = deadline
        self.deadlineDate = deadlineDate
        self.assignedToJson = assignedToJson
        self.assignedByJson = assignedByJson
        self.participantsJson = participantsJson
        self.meetingTitle = meetingTitle
        self.meetingDate = meetingDate
        self.aiDraft = aiDraft
        self.aiDraftType = aiDraftType
        self.slackThreadId = slackThreadId
        self.nudgeCount = nudgeCount
        self.lastNudgedAt = lastNudgedAt
        self.supabaseId = supabaseId
    }
}

// MARK: - GRDB conformance

extension ActionItem: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "action_items"

    enum Columns {
        static let id             = Column("id")
        static let task           = Column("task")
        static let source         = Column("source")
        static let sourceDetail   = Column("sourceDetail")
        static let isCompleted    = Column("isCompleted")  // legacy column kept
        static let status         = Column("status")
        static let createdAt      = Column("createdAt")
        static let deadline       = Column("deadline")
        static let deadlineDate   = Column("deadlineDate")
        static let assignedToJson    = Column("assignedToJson")
        static let assignedByJson    = Column("assignedByJson")
        static let participantsJson  = Column("participantsJson")
        static let meetingTitle   = Column("meetingTitle")
        static let meetingDate    = Column("meetingDate")
        static let aiDraft        = Column("aiDraft")
        static let aiDraftType    = Column("aiDraftType")
        static let slackThreadId  = Column("slackThreadId")
        static let nudgeCount     = Column("nudgeCount")
        static let lastNudgedAt   = Column("lastNudgedAt")
        static let supabaseId     = Column("supabaseId")
    }

    init(row: Row) {
        id             = row[Columns.id]
        task           = row[Columns.task] ?? ""
        source         = ActionItemSource(rawValue: row[Columns.source] ?? "") ?? .manual
        sourceDetail   = row[Columns.sourceDetail] ?? ""
        let statusRaw: String? = row[Columns.status]
        // Migrate old isCompleted boolean for legacy rows
        if let s = statusRaw, !s.isEmpty {
            status = ItemStatus(rawValue: s) ?? .todo
        } else {
            let completed: Bool = row[Columns.isCompleted] ?? false
            status = completed ? .done : .todo
        }
        createdAt      = row[Columns.createdAt] ?? Date()
        deadline       = row[Columns.deadline]
        deadlineDate   = row[Columns.deadlineDate]
        assignedToJson    = row[Columns.assignedToJson]
        assignedByJson    = row[Columns.assignedByJson]
        participantsJson  = row[Columns.participantsJson]
        meetingTitle   = row[Columns.meetingTitle]
        meetingDate    = row[Columns.meetingDate]
        aiDraft        = row[Columns.aiDraft]
        aiDraftType    = row[Columns.aiDraftType]
        slackThreadId  = row[Columns.slackThreadId]
        nudgeCount     = row[Columns.nudgeCount] ?? 0
        lastNudgedAt   = row[Columns.lastNudgedAt]
        supabaseId     = row[Columns.supabaseId]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id]             = id
        container[Columns.task]           = task
        container[Columns.source]         = source.rawValue
        container[Columns.sourceDetail]   = sourceDetail
        container[Columns.isCompleted]    = status == .done  // keep in sync for legacy
        container[Columns.status]         = status.rawValue
        container[Columns.createdAt]      = createdAt
        container[Columns.deadline]       = deadline
        container[Columns.deadlineDate]   = deadlineDate
        container[Columns.assignedToJson]    = assignedToJson
        container[Columns.assignedByJson]    = assignedByJson
        container[Columns.participantsJson]  = participantsJson
        container[Columns.meetingTitle]   = meetingTitle
        container[Columns.meetingDate]    = meetingDate
        container[Columns.aiDraft]        = aiDraft
        container[Columns.aiDraftType]    = aiDraftType
        container[Columns.slackThreadId]  = slackThreadId
        container[Columns.nudgeCount]     = nudgeCount
        container[Columns.lastNudgedAt]   = lastNudgedAt
        container[Columns.supabaseId]     = supabaseId
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - ExtractedActionItem (Claude API response)

struct ExtractedActionItem: Codable {
    let task: String
    let deadline: String?
    let assignedTo: String?   // person name as mentioned in transcript
    let assignedBy: String?   // person name who assigned it
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case task
        case deadline
        case assignedTo  = "assigned_to"
        case assignedBy  = "assigned_by"
        case confidence
    }
}
