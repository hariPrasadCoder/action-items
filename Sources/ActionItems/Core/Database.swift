import Foundation
import GRDB

class DatabaseManager {
    static let shared = DatabaseManager()
    var dbQueue: DatabaseQueue!

    private init() {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dbDir = appSupport.appendingPathComponent("ActionItems", isDirectory: true)
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            let dbPath = dbDir.appendingPathComponent("items.sqlite").path

            dbQueue = try DatabaseQueue(path: dbPath)
            try migrate()
        } catch {
            fatalError("Database init failed: \(error)")
        }
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_action_items") { db in
            try db.create(table: "action_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("task", .text).notNull()
                t.column("source", .text).notNull()
                t.column("sourceDetail", .text).notNull().defaults(to: "")
                t.column("isCompleted", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("deadline", .text)
            }
        }

        migrator.registerMigration("v2_add_deadline_date") { db in
            try db.alter(table: "action_items") { t in
                t.add(column: "deadlineDate", .datetime)
            }
        }

        migrator.registerMigration("v3_add_flax_fields") { db in
            try db.alter(table: "action_items") { t in
                t.add(column: "status", .text).notNull().defaults(to: "todo")
                t.add(column: "assignedToJson", .text)
                t.add(column: "assignedByJson", .text)
                t.add(column: "participantsJson", .text)
                t.add(column: "meetingTitle", .text)
                t.add(column: "meetingDate", .datetime)
                t.add(column: "aiDraft", .text)
                t.add(column: "aiDraftType", .text)
                t.add(column: "slackThreadId", .text)
                t.add(column: "nudgeCount", .integer).notNull().defaults(to: 0)
                t.add(column: "lastNudgedAt", .datetime)
                t.add(column: "supabaseId", .text)
            }
            // Migrate existing completed items to 'done' status
            try db.execute(sql: "UPDATE action_items SET status = 'done' WHERE isCompleted = 1")
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - CRUD

    func save(_ item: inout ActionItem) throws {
        try dbQueue.write { db in
            try item.save(db)
        }
    }

    func fetchAll() throws -> [ActionItem] {
        try dbQueue.read { db in
            try ActionItem.order(ActionItem.Columns.createdAt.desc).fetchAll(db)
        }
    }

    func fetchPending() throws -> [ActionItem] {
        try dbQueue.read { db in
            try ActionItem
                .filter(ActionItem.Columns.status != ItemStatus.done.rawValue)
                .order(ActionItem.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func fetchDelegated(currentUserEmail: String?) throws -> [ActionItem] {
        try dbQueue.read { db in
            let all = try ActionItem
                .filter(ActionItem.Columns.status != ItemStatus.done.rawValue)
                .fetchAll(db)
            return all.filter { item in
                guard let assignedTo = item.assignedTo else { return false }
                if assignedTo.isCurrentUser { return false }
                if let email = currentUserEmail, let assigneeEmail = assignedTo.email {
                    return email.lowercased() != assigneeEmail.lowercased()
                }
                return true
            }
        }
    }

    func fetchPendingForNudge() throws -> [ActionItem] {
        try dbQueue.read { db in
            let sixHoursAgo = Date().addingTimeInterval(-6 * 3600)
            return try ActionItem
                .filter(ActionItem.Columns.status != ItemStatus.done.rawValue)
                .filter(ActionItem.Columns.status != ItemStatus.blocked.rawValue)
                .fetchAll(db)
                .filter { item in
                    if let lastNudged = item.lastNudgedAt, lastNudged > sixHoursAgo { return false }
                    return true
                }
        }
    }

    func updateStatus(_ item: ActionItem, status: ItemStatus) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE action_items SET status = ?, isCompleted = ? WHERE id = ?",
                arguments: [status.rawValue, status == .done, item.id]
            )
        }
    }

    func toggleCompleted(_ item: ActionItem) throws {
        let newStatus: ItemStatus = item.status == .done ? .todo : .done
        try updateStatus(item, status: newStatus)
    }

    func updateTask(_ item: ActionItem, newTask: String, newDeadline: String?, newDeadlineDate: Date?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE action_items SET task = ?, deadline = ?, deadlineDate = ? WHERE id = ?",
                arguments: [newTask, newDeadline, newDeadlineDate, item.id]
            )
        }
    }

    func updateAIDraft(_ item: ActionItem, draft: String, type: AIDraftType) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE action_items SET aiDraft = ?, aiDraftType = ? WHERE id = ?",
                arguments: [draft, type.rawValue, item.id]
            )
        }
    }

    func updateNudgeTracking(_ item: ActionItem) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE action_items SET nudgeCount = nudgeCount + 1, lastNudgedAt = ? WHERE id = ?",
                arguments: [Date(), item.id]
            )
        }
    }

    func updateSupabaseId(_ item: ActionItem, supabaseId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE action_items SET supabaseId = ? WHERE id = ?",
                arguments: [supabaseId, item.id]
            )
        }
    }

    func delete(_ item: ActionItem) throws {
        try dbQueue.write { db in
            _ = try item.delete(db)
        }
    }
}
