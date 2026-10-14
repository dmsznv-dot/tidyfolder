import Foundation
import Testing
@testable import TidyCore
struct CrashExecutionTests {
    @Test(arguments: ["afterPrepare", "beforePublish", "afterPublish", "afterCommit", "afterComplete"])
    func interruptedMoveCanBeRestored(checkpoint: String) async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("source/a.pdf", "crash-safe")
        let process = Process(); process.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build-working/debug/TidyHarness")
        process.arguments = [t.url("source").path, t.url("out").path, t.url("history.db").path, checkpoint]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 89)
        let journal = try SQLiteJournal(url: t.url("history.db")); let run = try #require(try await journal.runs().first)
        let result = try await ExecutionCoordinator(journal: journal).undo(runID: run.id)
        #expect(result.issues.isEmpty); #expect(try String(contentsOf: t.url("source/a.pdf"), encoding: .utf8) == "crash-safe")
    }
}
