import Foundation
import Testing
@testable import TidyCore
struct CrashUndoTests {
    @Test(arguments: ["afterPrepare", "afterPublish", "afterCommit"])
    func crashUndoRestart(checkpoint: String) async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("source/a.pdf", "undo-safe")
        let plan = try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: .init(), now: .now)
        let journal = try SQLiteJournal(url: t.url("history.db")); _ = try await ExecutionCoordinator(journal: journal).execute(plan: plan)
        let process = Process(); process.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build-working/debug/TidyHarness")
        process.arguments = [t.url("source").path, t.url("out").path, t.url("history.db").path, checkpoint, "undo:\(plan.id.uuidString)"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 89)
        let result = try await ExecutionCoordinator(journal: try SQLiteJournal(url: t.url("history.db"))).undo(runID: plan.id)
        #expect(result.issues.isEmpty); #expect(try String(contentsOf: t.url("source/a.pdf"), encoding: .utf8) == "undo-safe")
        #expect(!PathSafety.exists(t.url("out/PDFs/a.pdf")))
    }
}
