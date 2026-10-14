import Foundation
import CSQLite
private final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer
    init(_ handle: OpaquePointer) { self.handle = handle }
    deinit { sqlite3_close_v2(handle) }
}
public actor SQLiteJournal: JournalStore {
    private let connection: SQLiteConnection
    private let leaseURL: URL
    private var db: OpaquePointer { connection.handle }
    public init(url: URL, createParent: Bool = true) throws {
        if createParent { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
        var ptr: OpaquePointer?
        guard sqlite3_open_v2(url.path, &ptr, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let ptr else {
            if let ptr { sqlite3_close(ptr) }; throw TidyError.io("Cannot open history: \(url.path)")
        }
        let conn = SQLiteConnection(ptr)
        sqlite3_busy_timeout(ptr, 5000)
        let version = try Self.query(ptr, "PRAGMA user_version").first.flatMap(Int.init) ?? 0
        guard version <= 1 else { throw TidyError.newerSchema }
        try Self.execute(ptr, "PRAGMA journal_mode=WAL")
        try Self.execute(ptr, "PRAGMA synchronous=FULL")
        try Self.execute(ptr, "PRAGMA fullfsync=ON")
        try Self.execute(ptr, "PRAGMA checkpoint_fullfsync=ON")
        try Self.execute(ptr, "CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY, data TEXT NOT NULL); CREATE TABLE IF NOT EXISTS operations(id TEXT PRIMARY KEY, run_id TEXT NOT NULL, data TEXT NOT NULL); CREATE INDEX IF NOT EXISTS ops_by_run ON operations(run_id); PRAGMA user_version=1")
        guard try Self.query(ptr, "PRAGMA synchronous").first == "2", try Self.query(ptr, "PRAGMA journal_mode").first == "wal" else { throw TidyError.io("History durability settings unavailable") }
        try Self.validatePersistedRecords(ptr)
        connection = conn
        leaseURL = PathSafety.canonical(url).appendingPathExtension("run-lock")
    }
    private static func validatePersistedRecords(_ db: OpaquePointer) throws {
        guard try query(db, "PRAGMA quick_check") == ["ok"] else { throw TidyError.io("History integrity check failed") }
        let decoder = JSONDecoder()
        let runs = try query(db, "SELECT data FROM runs").map { try decoder.decode(RunRecord.self, from: Data($0.utf8)) }
        let operations = try query(db, "SELECT data FROM operations").map { try decoder.decode(OperationRecord.self, from: Data($0.utf8)) }
        var runIDs = Set<UUID>(), operationIDs = Set<UUID>()
        for run in runs {
            guard runIDs.insert(run.id).inserted, run.plan.id == run.id,
                  try query(db, "SELECT id FROM runs WHERE id=?", values: [run.id.uuidString]).count == 1 else { throw TidyError.io("Invalid history run relationship") }
        }
        for op in operations {
            guard operationIDs.insert(op.id).inserted, runIDs.contains(op.runID),
                  try query(db, "SELECT id FROM operations WHERE id=? AND run_id=?", values: [op.id.uuidString, op.runID.uuidString]).count == 1 else { throw TidyError.io("Invalid history operation relationship") }
        }
        let grouped = Dictionary(grouping: operations, by: \.runID)
        for run in runs {
            guard Set(run.plan.operations.map(\.id)) == Set((grouped[run.id] ?? []).map(\.id)),
                  run.undoOfRun.map({ runIDs.contains($0) }) ?? true else { throw TidyError.io("Incomplete history run") }
        }
        for op in operations where op.undoOf != nil {
            guard operationIDs.contains(op.undoOf!) else { throw TidyError.io("Invalid history undo relationship") }
        }
    }
    public func acquireRunLease() throws -> RunLease { try RunLease(url: leaseURL) }
    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw TidyError.io("History: \(String(cString: sqlite3_errmsg(db)))") }
    }
    private static func query(_ db: OpaquePointer, _ sql: String, values: [String] = []) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TidyError.io("History: \(String(cString: sqlite3_errmsg(db)))") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() { guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else { throw TidyError.io("History bind failed") } }
        var output: [String] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return output }
            guard code == SQLITE_ROW else { throw TidyError.io("History: \(String(cString: sqlite3_errmsg(db)))") }
            if let text = sqlite3_column_text(statement, 0) { output.append(String(cString: text)) }
        }
    }
    private func encode<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T { try JSONDecoder().decode(type, from: Data(text.utf8)) }
    private func transaction<T>(_ action: () throws -> T) throws -> T {
        try Self.execute(db, "BEGIN IMMEDIATE")
        do { let result = try action(); try Self.execute(db, "COMMIT"); return result } catch { try? Self.execute(db, "ROLLBACK"); throw error }
    }
    public func prepare(plan: TidyPlan) throws -> RunRecord {
        let run = RunRecord(id: plan.id, plan: plan, status: "running", directories: [])
        return try transaction {
            _ = try Self.query(db, "INSERT INTO runs(id,data) VALUES(?,?)", values: [run.id.uuidString, encode(run)])
            for op in plan.operations {
                let record = OperationRecord(runID: run.id, operation: op, state: .prepared)
                _ = try Self.query(db, "INSERT INTO operations(id,run_id,data) VALUES(?,?,?)", values: [op.id.uuidString, run.id.uuidString, encode(record)])
            }
            return run
        }
    }
    private func operation(_ id: UUID) throws -> OperationRecord {
        guard let row = try Self.query(db, "SELECT data FROM operations WHERE id=?", values: [id.uuidString]).first else { throw TidyError.io("Operation missing in history") }
        return try decode(OperationRecord.self, row)
    }
    private func update(_ record: OperationRecord) throws { _ = try Self.query(db, "UPDATE operations SET data=? WHERE id=?", values: [encode(record), record.id.uuidString]) }
    private func run(_ id: UUID) throws -> RunRecord {
        guard let row = try Self.query(db, "SELECT data FROM runs WHERE id=?", values: [id.uuidString]).first else { throw TidyError.io("Run missing in history") }
        return try decode(RunRecord.self, row)
    }
    private func update(_ run: RunRecord) throws { _ = try Self.query(db, "UPDATE runs SET data=? WHERE id=?", values: [encode(run), run.id.uuidString]) }
    public func transition(operationID: UUID, to: OperationState, evidence: OperationEvidence?) throws {
        var op = try operation(operationID)
        let allowed: [OperationState: [OperationState]] = [.prepared: [.copying,.publishIntent,.conflict,.failed], .copying: [.verified,.conflict,.failed], .verified: [.publishIntent,.conflict,.failed], .publishIntent: [.committed,.conflict,.failed], .committed: [.deleteIntent,.completed,.conflict,.failed], .deleteIntent: [.sourceRemoved,.conflict,.failed], .sourceRemoved: [.completed,.failed]]
        guard allowed[op.state]?.contains(to) == true else { throw TidyError.io("Invalid operation transition \(op.state.rawValue) → \(to.rawValue)") }
        op.state = to; if let evidence { op.evidence = evidence }
        try update(op)
    }
    public func finish(runID: UUID, result: RunSummary) throws {
        var r = try run(runID); r.summary = result; r.status = result.cancelled ? "cancelled" : result.failed > 0 || result.sourceRetained > 0 ? "partial" : "completed"; try update(r)
    }
    public func runs() throws -> [RunRecord] { try Self.query(db, "SELECT data FROM runs ORDER BY rowid DESC").map { try decode(RunRecord.self, $0) } }
    public func operations(runID: UUID) throws -> [OperationRecord] { try Self.query(db, "SELECT data FROM operations WHERE run_id=? ORDER BY rowid", values: [runID.uuidString]).map { try decode(OperationRecord.self, $0) } }
    public func incompleteRuns() throws -> [RunRecord] { try runs().filter { $0.status == "running" } }
    public func registerDirectory(runID: UUID, directory: OwnedDirectory) throws {
        var r = try run(runID)
        if let index = r.directories.firstIndex(where: { $0.url == directory.url }) { r.directories[index] = directory } else { r.directories.append(directory) }
        try update(r)
    }
    public func markRestored(operationID: UUID) throws {
        var op = try operation(operationID); op.state = .restored; try update(op)
    }
    public func finishUndo(originalRunID: UUID, result: RunSummary) throws {
        var r = try run(originalRunID)
        let allRestored = try operations(runID: originalRunID).allSatisfy { $0.state == .restored }
        r.status = allRestored && result.failed == 0 && !result.cancelled ? "restored" : "partial"
        try update(r)
    }
    public func markUndo(runID: UUID, originalRunID: UUID) throws {
        var r = try run(runID); r.undoOfRun = originalRunID; try update(r)
        func key(_ source: URL, _ destination: URL) -> String { source.standardizedFileURL.path + "\0" + destination.standardizedFileURL.path }
        let originals = try Dictionary(uniqueKeysWithValues: operations(runID: originalRunID).map { (key($0.operation.source.url, $0.operation.destination), $0.id) })
        for var reverse in try operations(runID: runID) {
            reverse.undoOf = originals[key(reverse.operation.destination, reverse.operation.source.url)]
            try update(reverse)
        }
    }
    public func appendOperations(runID: UUID, operations extra: [PlannedOperation]) throws {
        try transaction {
            var r = try run(runID); r.plan.operations.append(contentsOf: extra); try update(r)
            for op in extra { let record = OperationRecord(runID: runID, operation: op, state: .prepared); _ = try Self.query(db, "INSERT INTO operations(id,run_id,data) VALUES(?,?,?)", values: [op.id.uuidString, runID.uuidString, encode(record)]) }
        }
    }
    public func registerRemovedDirectory(runID: UUID, directory: DirectoryBackup) throws {
        var r = try run(runID)
        if !r.removedDirectories.contains(where: { $0.url == directory.url }) { r.removedDirectories.append(directory); try update(r) }
    }
}
