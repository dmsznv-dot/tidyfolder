import Foundation
import Testing
@testable import TidyCore
struct RecoveryTests {
    @Test func removedEmptyDirectoryRestoredWithoutReverseFiles() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("source/a.pdf", "file")
        try FileManager.default.createDirectory(at: t.url("source/empty/nested"), withIntermediateDirectories: true)
        var options = ScanOptions(); options.recursive = true; options.removeEmptyFolders = true
        let p = try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: options, now: .now)
        let journal = try SQLiteJournal(url: t.url("history.db")), runner = ExecutionCoordinator(journal: journal)
        _ = try await runner.execute(plan: p)
        #expect(!PathSafety.exists(t.url("source/empty")))
        let result = try await runner.undo(runID: p.id)
        #expect(result.failed == 0)
        #expect(PathSafety.exists(t.url("source/empty/nested")))
        let second = try await runner.undo(runID: p.id); #expect(second.failed == 0)
    }

    func sorted(_ t: TestTree, cleanup: Bool = false) async throws -> TidyPlan {
        try t.put("source/nested/a.pdf", "restore me"); if cleanup { try t.put("source/nested/.DS_Store", "metadata") }
        var options = ScanOptions(); options.recursive = true; options.removeEmptyFolders = cleanup
        let p = try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: options, now: .now)
        let journal = try SQLiteJournal(url: t.url("history.db")); _ = try await ExecutionCoordinator(journal: journal).execute(plan: p); return p
    }
    @Test func sortRestartUndoRestoresTree() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await sorted(t)
        let runner = ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db"))); let result = try await runner.undo(runID: p.id)
        #expect(result.failed == 0, Comment(rawValue: result.issues.joined(separator: "; ")))
        #expect(result.moved == 1); #expect(try String(contentsOf: t.url("source/nested/a.pdf"), encoding: .utf8) == "restore me")
        #expect(!PathSafety.exists(t.url("out/PDFs/a.pdf")))
    }
    @Test func occupiedOriginalPathPreservesBoth() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await sorted(t); try t.put("source/nested/a.pdf", "new file")
        let result = try await ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db"))).undo(runID: p.id)
        #expect(result.moved == 0); #expect(result.issues.isEmpty == false)
        #expect(try String(contentsOf: t.url("source/nested/a.pdf"), encoding: .utf8) == "new file"); #expect(PathSafety.exists(t.url("out/PDFs/a.pdf")))
    }
    @Test func editedDestinationRefusesUndo() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await sorted(t); try t.put("out/PDFs/a.pdf", "new edit")
        let result = try await ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db"))).undo(runID: p.id)
        #expect(result.moved == 0); #expect(result.issues.isEmpty == false); #expect(PathSafety.exists(t.url("out/PDFs/a.pdf")))
    }
    @Test func replacedIdentityRefusesUndo() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await sorted(t); try FileManager.default.removeItem(at: t.url("out/PDFs/a.pdf")); try t.put("out/PDFs/a.pdf", "restore me")
        let result = try await ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db"))).undo(runID: p.id)
        #expect(result.moved == 0); #expect(result.issues.isEmpty == false)
    }
    @Test func missingDestinationReported() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await sorted(t); try FileManager.default.removeItem(at: t.url("out/PDFs/a.pdf"))
        let result = try await ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db"))).undo(runID: p.id)
        #expect(result.issues.isEmpty == false)
    }
    @Test func secondUndoIdempotent() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await sorted(t); let runner = ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db")))
        _ = try await runner.undo(runID: p.id); let second = try await runner.undo(runID: p.id)
        #expect(second.moved == 0); #expect(second.issues.isEmpty)
    }
    @Test func newFilesInCreatedFolderKept() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await sorted(t); try t.put("out/PDFs/new.txt", "keep")
        _ = try await ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db"))).undo(runID: p.id)
        #expect(try String(contentsOf: t.url("out/PDFs/new.txt"), encoding: .utf8) == "keep")
    }
    @Test func hiddenMetadataRestored() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let p = try await sorted(t, cleanup: true)
        #expect(!PathSafety.exists(t.url("source/nested")))
        _ = try await ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db"))).undo(runID: p.id)
        #expect(try String(contentsOf: t.url("source/nested/.DS_Store"), encoding: .utf8) == "metadata")
        #expect(try String(contentsOf: t.url("source/nested/a.pdf"), encoding: .utf8) == "restore me")
    }
}
