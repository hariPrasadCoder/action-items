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

        try migrator.migrate(dbQueue)
    }

    // MARK: - CRUD

    func save(_ item: inout ActionItem) throws {
        try dbQueue.write { db in
            try item.save(db)
        }
    }

    func saveAll(_ items: [ActionItem], source: ActionItemSource, sourceDetail: String) throws {
        try dbQueue.write { db in
            for var item in items {
                var mutable = item
                mutable.source = source
                mutable.sourceDetail = sourceDetail
                try mutable.save(db)
            }
        }
    }

    func fetchAll() throws -> [ActionItem] {
        try dbQueue.read { db in
            try ActionItem.order(ActionItem.Columns.createdAt.desc).fetchAll(db)
        }
    }

    func fetchPending() throws -> [ActionItem] {
        try dbQueue.read { db in
            try ActionItem.filter(ActionItem.Columns.isCompleted == false)
                .order(ActionItem.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func toggleCompleted(_ item: ActionItem) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE action_items SET isCompleted = ? WHERE id = ?",
                arguments: [!item.isCompleted, item.id]
            )
        }
    }

    func delete(_ item: ActionItem) throws {
        try dbQueue.write { db in
            _ = try item.delete(db)
        }
    }
}
