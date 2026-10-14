import Foundation
import Testing
import CSQLite
@testable import TidyCore
struct JournalTests {
    @Test func damagedOperationPayloadBlocksOpeningHistory() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await plan(t)
        let store = try SQLiteJournal(url: t.url("journal.db")); _ = try await store.prepare(plan: p)
        var db: OpaquePointer?; #expect(sqlite3_open(t.url("journal.db").path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "UPDATE operations SET data='broken JSON'", nil, nil, nil) == SQLITE_OK)
        #expect(throws: Error.self) { try SQLiteJournal(url: t.url("journal.db")) }
        #expect(PathSafety.exists(t.url("source/a.pdf")))
    }

    func plan(_ t: TestTree) async throws -> TidyPlan {
        try t.put("source/a.pdf", "journal"); return try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: .init(), now: .now)
    }
    @Test func reopenPreservesIntent() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await plan(t)
        let store = try SQLiteJournal(url: t.url("journal.db")); _ = try await store.prepare(plan: p)
        let reopened = try SQLiteJournal(url: t.url("journal.db"))
        #expect(try await reopened.runs().count == 1)
        let rows = try await reopened.operations(runID: p.id)
        #expect(rows.first?.operation.source.url.resolvingSymlinksInPath() == t.url("source/a.pdf").resolvingSymlinksInPath())
    }
    @Test func transitionWithEvidenceAtomic() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await plan(t); let store = try SQLiteJournal(url: t.url("journal.db")); _ = try await store.prepare(plan: p)
        let evidence = OperationEvidence(sourceDigest: "digest", stagingURL: t.url("staging"))
        try await store.transition(operationID: p.operations[0].id, to: .copying, evidence: evidence)
        let reopened = try SQLiteJournal(url: t.url("journal.db")); let rows = try await reopened.operations(runID: p.id); let record = try #require(rows.first)
        #expect(record.state == .copying); #expect(record.evidence?.stagingURL == t.url("staging"))
    }
    @Test func invalidTransitionRejected() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await plan(t); let store = try SQLiteJournal(url: t.url("journal.db")); _ = try await store.prepare(plan: p)
        await #expect(throws: Error.self) { try await store.transition(operationID: UUID(), to: .completed, evidence: nil) }
        await #expect(throws: Error.self) { try await store.transition(operationID: p.operations[0].id, to: .completed, evidence: nil) }
    }
    @Test func newerSchemaFailsClosed() throws {
        let t = try TestTree(); defer { t.cleanup() }; var db: OpaquePointer?
        #expect(sqlite3_open(t.url("journal.db").path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "PRAGMA user_version=999", nil, nil, nil) == SQLITE_OK)
        #expect(throws: TidyError.newerSchema) { try SQLiteJournal(url: t.url("journal.db")) }
    }
    @Test func corruptStoreFailsClosed() throws {
        let t = try TestTree(); defer { t.cleanup() }; let db = try t.put("journal.db", "not sqlite")
        #expect(throws: Error.self) { try SQLiteJournal(url: db) }
        #expect(try String(contentsOf: db, encoding: .utf8) == "not sqlite")
    }
    @Test func writeFailurePreventsMutation() throws {
        let t = try TestTree(); defer { t.cleanup() }; #expect(throws: Error.self) { try SQLiteJournal(url: t.url("missing/child/journal.db"), createParent: false) }
    }
}
