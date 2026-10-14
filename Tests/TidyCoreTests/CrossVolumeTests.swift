import Foundation
import Testing
@testable import TidyCore
struct ForcedCrossVolumeFS: FileSystem {
    let base = LocalFileSystem()
    let root: URL
    var failRename = false
    func snapshot(at url: URL) throws -> FileSnapshot { var s = try base.snapshot(at: url); if s.isDirectory && PathSafety.contains(root, url) { s.fingerprint.identity.device = UInt64.max }; return s }
    func renameExclusive(from: URL, to: URL) throws { if failRename { throw TidyError.unsupported(to.path) }; try base.renameExclusive(from: from, to: to) }
    func copyExclusive(from: URL, to: URL) throws { try base.copyExclusive(from: from, to: to) }
    func verifyCopy(source: URL, copy: URL, expected: FileFingerprint) throws -> VerificationEvidence { try base.verifyCopy(source: source, copy: copy, expected: expected) }
    func synchronize(at: URL) throws { try base.synchronize(at: at) }
    func removeSource(at: URL, expected: VerificationEvidence) throws { try base.removeSource(at: at, expected: expected) }
    func createDirectoryExclusive(at: URL) throws { try base.createDirectoryExclusive(at: at) }
    func removeDirectoryIfEmpty(at: URL) throws { try base.removeDirectoryIfEmpty(at: at) }
}
struct CrossVolumeTests {
    @Test func cancellationAfterFinalPublicationReportsRetainedSource() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("source/a.pdf", "retained")
        let p = try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: .init(), now: .now)
        let signal = AsyncStream<Void>.makeStream()
        let runner = ExecutionCoordinator(fileSystem: ForcedCrossVolumeFS(root: t.url("out")), journal: try SQLiteJournal(url: t.url("history.db")), checkpoint: { point, _ in
            if point == .afterCommit { signal.continuation.yield(()); try await Task.sleep(for: .milliseconds(100)) }
        })
        let running = Task { try await runner.execute(plan: p) }
        var iterator = signal.stream.makeAsyncIterator(); _ = await iterator.next(); await runner.cancel()
        let result = try await running.value
        #expect(result.cancelled); #expect(result.copied == 1); #expect(result.sourceRetained == 1)
        #expect(PathSafety.exists(t.url("source/a.pdf"))); #expect(PathSafety.exists(t.url("out/PDFs/a.pdf")))
    }

    @Test(arguments: ["missing", "modified", "replaced", "symlink"])
    func publishedCopyMustStillExistBeforeRemovingSource(change: String) async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("source/a.pdf", "only original")
        let p = try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: .init(), now: .now)
        let target = t.url("out/PDFs/a.pdf")
        let runner = ExecutionCoordinator(fileSystem: ForcedCrossVolumeFS(root: t.url("out")), journal: try SQLiteJournal(url: t.url("history.db")), checkpoint: { point, _ in
            if point == .beforeSourceRemoval {
                if change != "modified" { try FileManager.default.removeItem(at: target) }
                if change == "modified" { try Data("edited copy".utf8).write(to: target) }
                if change == "replaced" { try Data("replacement".utf8).write(to: target) }
                if change == "symlink" { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: t.url("source/a.pdf")) }
            }
        })
        let result = try await runner.execute(plan: p)
        #expect(result.failed == 1); #expect(result.moved == 0)
        #expect(PathSafety.exists(t.url("source/a.pdf")))
        if PathSafety.exists(t.url("source/a.pdf")) { #expect(try String(contentsOf: t.url("source/a.pdf"), encoding: .utf8) == "only original") }
    }

    @Test(arguments: [ExecutionCheckpoint.beforeSourceRemoval, .afterSourceRemoval])
    func interruptedCrossVolumeMoveRestoresData(point: ExecutionCheckpoint) async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("source/a.pdf", "cross-crash")
        let p = try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: .init(), now: .now)
        let journal = try SQLiteJournal(url: t.url("history.db")); let fs = ForcedCrossVolumeFS(root: t.url("out"))
        _ = try await ExecutionCoordinator(fileSystem: fs, journal: journal, checkpoint: { at, _ in if at == point { throw TidyError.io("injected interruption") } }).execute(plan: p)
        let result = try await ExecutionCoordinator(journal: journal).undo(runID: p.id)
        #expect(result.issues.isEmpty); #expect(try String(contentsOf: t.url("source/a.pdf"), encoding: .utf8) == "cross-crash")
        #expect(!PathSafety.exists(t.url("out/PDFs/a.pdf")))
    }
    @Test func undoRetainedVerifiedCopyPreservesOriginal() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("source/a.pdf", "retained")
        let p = try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: .init(), now: .now)
        let journal = try SQLiteJournal(url: t.url("history.db")); let fs = ForcedCrossVolumeFS(root: t.url("out"))
        _ = try await ExecutionCoordinator(fileSystem: fs, journal: journal, checkpoint: { point, _ in if point == .afterPublish { throw TidyError.io("injected stop") } }).execute(plan: p)
        #expect(PathSafety.exists(t.url("source/a.pdf"))); #expect(PathSafety.exists(t.url("out/PDFs/a.pdf")))
        let result = try await ExecutionCoordinator(journal: journal).undo(runID: p.id)
        #expect(result.issues.isEmpty); #expect(!PathSafety.exists(t.url("out/PDFs/a.pdf")))
        #expect(try String(contentsOf: t.url("source/a.pdf"), encoding: .utf8) == "retained")
    }
    @Test func crossVolumeCopyVerifyPublishDelete() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("source/a.pdf", "cross-volume")
        let p = try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: .init(), now: .now)
        let journal = try SQLiteJournal(url: t.url("history.db")); let fs = ForcedCrossVolumeFS(root: t.url("out"))
        let result = try await ExecutionCoordinator(fileSystem: fs, journal: journal).execute(plan: p)
        #expect(result.failed == 0, Comment(rawValue: result.issues.joined(separator: "; ")))
        #expect(result.moved == 1); #expect(result.copied == 1); #expect(!PathSafety.exists(t.url("source/a.pdf")))
        #expect(try String(contentsOf: t.url("out/PDFs/a.pdf"), encoding: .utf8) == "cross-volume")
        #expect(try await journal.operations(runID: p.id).first?.evidence?.verification != nil)
    }
    @Test func unsupportedRenameFailsClosed() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("source/a.pdf", "preserve")
        let p = try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: .init(), now: .now)
        let fs = ForcedCrossVolumeFS(root: t.url("out"), failRename: true)
        let result = try await ExecutionCoordinator(fileSystem: fs, journal: try SQLiteJournal(url: t.url("history.db"))).execute(plan: p)
        #expect(result.moved == 0); #expect(PathSafety.exists(t.url("source/a.pdf"))); #expect(!PathSafety.exists(t.url("out/PDFs/a.pdf")))
    }
}
