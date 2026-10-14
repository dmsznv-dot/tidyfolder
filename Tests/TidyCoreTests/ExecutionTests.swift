import Foundation
import Testing
@testable import TidyCore
struct ExecutionTests {
    @Test func executionRefusesProtectedStoreEvenWithUnprotectedPlan() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await plan(t)
        let runner = ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db")), protectedURLs: [t.url("source")])
        await #expect(throws: Error.self) { try await runner.execute(plan: p) }
        #expect(PathSafety.exists(t.url("source/file0.pdf")))
    }

    @Test func separateCoordinatorsShareJournalLease() async throws {
        let t = try TestTree(), other = try TestTree(); defer { t.cleanup(); other.cleanup() }
        let firstPlan = try await plan(t), secondPlan = try await plan(other)
        let database = t.url("history.db")
        let firstRunner = ExecutionCoordinator(journal: try SQLiteJournal(url: database), checkpoint: { point, _ in if point == .afterPrepare { try await Task.sleep(for: .milliseconds(150)) } })
        let secondRunner = ExecutionCoordinator(journal: try SQLiteJournal(url: database))
        let first = Task { try await firstRunner.execute(plan: firstPlan) }
        try await Task.sleep(for: .milliseconds(30))
        await #expect(throws: TidyError.busy) { try await secondRunner.execute(plan: secondPlan) }
        _ = try await first.value
        #expect(PathSafety.exists(other.url("source/file0.pdf")))
    }

    func plan(_ t: TestTree, files: Int = 1) async throws -> TidyPlan {
        for i in 0..<files { try t.put("source/file\(i).pdf", "contents\(i)") }
        return try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: .init(), now: .now)
    }
    @Test func sameVolumeSort() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await plan(t); let journal = try SQLiteJournal(url: t.url("history.db")); let runner = ExecutionCoordinator(journal: journal)
        let result = try await runner.execute(plan: p)
        #expect(result.failed == 0, Comment(rawValue: result.issues.joined(separator: "; ")))
        #expect(result.moved == 1); #expect(!PathSafety.exists(t.url("source/file0.pdf")))
        #expect(try String(contentsOf: t.url("out/PDFs/file0.pdf"), encoding: .utf8) == "contents0")
        #expect(try await journal.operations(runID: p.id).first?.state == .completed)
    }
    @Test func changedSincePreviewSkipped() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await plan(t); try Data("changed".utf8).write(to: t.url("source/file0.pdf"))
        let runner = ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db")))
        let result = try await runner.execute(plan: p); #expect(result.moved == 0); #expect(PathSafety.exists(t.url("source/file0.pdf")))
    }
    @Test func destinationRaceNeverOverwrites() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await plan(t); try t.put("out/PDFs/file0.pdf", "other")
        let runner = ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db")))
        let result = try await runner.execute(plan: p); #expect(result.moved == 0); #expect(try String(contentsOf: t.url("out/PDFs/file0.pdf"), encoding: .utf8) == "other")
    }
    @Test func oneRunAcrossActorReentrancy() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await plan(t)
        let runner = ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db")), checkpoint: { point, _ in if point == .afterPrepare { try await Task.sleep(for: .milliseconds(100)) } })
        let first = Task { try await runner.execute(plan: p) }; try await Task.sleep(for: .milliseconds(20))
        await #expect(throws: TidyError.busy) { try await runner.execute(plan: p) }
        _ = try await first.value
    }
    @Test func cancelStopsNewOperations() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await plan(t, files: 4)
        let runner = ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db")), checkpoint: { point, _ in if point == .afterPrepare { try await Task.sleep(for: .milliseconds(100)) } })
        let running = Task { try await runner.execute(plan: p) }; try await Task.sleep(for: .milliseconds(20)); await runner.cancel()
        let result = try await running.value; #expect(result.cancelled); #expect(result.moved == 0)
    }
    @Test func zeroPlanDoesNotCreateRun() async throws {
        let t = try TestTree(); defer { t.cleanup() }; var p = try await plan(t); p.operations = []
        let journal = try SQLiteJournal(url: t.url("history.db")); _ = try await ExecutionCoordinator(journal: journal).execute(plan: p)
        #expect(try await journal.runs().isEmpty)
    }
    @Test func journalFailureStopsChanges() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await plan(t)
        let journal = try SQLiteJournal(url: t.url("history.db")); _ = try await journal.prepare(plan: p)
        await #expect(throws: Error.self) { try await ExecutionCoordinator(journal: journal).execute(plan: p) }
        #expect(PathSafety.exists(t.url("source/file0.pdf")))
    }
}
