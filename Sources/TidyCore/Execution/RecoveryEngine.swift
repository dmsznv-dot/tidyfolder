import Foundation
public struct RecoveryReport: Sendable { public var restored = 0; public var retained = 0; public var conflicts: [String] = [] }
extension ExecutionCoordinator {
    private func owned(_ snapshot: FileSnapshot, record: OperationRecord) throws -> Bool {
        guard let e = record.evidence, !e.sourceDigest.isEmpty else { return false }
        let expected = e.destinationFingerprint ?? e.stagingFingerprint ?? (e.verification == nil ? record.operation.source.fingerprint : nil)
        guard let expected, snapshot.fingerprint == expected else { return false }
        return try FileVerification.digest(at: snapshot.url) == e.sourceDigest
    }
    public func undo(runID: UUID) async throws -> RunSummary {
        guard !active else { throw TidyError.busy }; active = true; cancelled = false; defer { active = false }
        let lease = try await journal.acquireRunLease(); defer { withExtendedLifetime(lease) {} }
        guard let original = try await journal.runs().first(where: { $0.id == runID }) else { throw TidyError.io("Run not found") }
        guard original.undoOfRun == nil else { throw TidyError.unsupported("Restore the original run instead of reversing an undo") }
        if original.status == "restored" { return RunSummary(runID: UUID()) }
        var report = RunSummary(runID: UUID()), reverse: [PlannedOperation] = []
        let runs = try await journal.runs()
        var previousUndo: [OperationRecord] = []
        for r in runs where r.undoOfRun == runID { previousUndo += try await journal.operations(runID: r.id) }
        for record in try await journal.operations(runID: runID) where record.state != .restored {
            let source = record.operation.source.url, target = record.operation.destination
            do {
                if PathSafety.exists(source) && !PathSafety.exists(target) {
                    let current = try fileSystem.snapshot(at: source)
                    let untouched = try current.fingerprint == record.operation.source.fingerprint && (record.evidence == nil || FileVerification.digest(at: source) == record.evidence?.sourceDigest)
                    let restored = try previousUndo.contains { candidate in guard candidate.undoOf == record.id else { return false }; return try owned(current, record: candidate) }
                    if untouched || restored {
                        if let stage = record.evidence?.stagingURL, PathSafety.exists(stage) { report.issues.append("Temporary copy retained for inspection: \(stage.path)") }
                        else { try await journal.markRestored(operationID: record.id) }
                        continue
                    }
                }
                if PathSafety.exists(source), PathSafety.exists(target), record.evidence?.verification != nil {
                    let originalSource = try fileSystem.snapshot(at: source), copy = try fileSystem.snapshot(at: target)
                    if originalSource.fingerprint == record.operation.source.fingerprint, try owned(copy, record: record), try FileVerification.digest(at: source) == record.evidence?.sourceDigest {
                        reverse.append(.init(source: copy, destination: source, ruleID: record.operation.ruleID, removesVerifiedCopy: true)); continue
                    }
                }
                guard !PathSafety.exists(source) else { throw TidyError.conflict(source.path) }
                guard PathSafety.exists(target) else { throw TidyError.io("Missing file: \(target.path)") }
                let snapshot = try fileSystem.snapshot(at: target)
                guard try owned(snapshot, record: record) else { throw TidyError.changed(target.path) }
                reverse.append(.init(source: snapshot, destination: source, ruleID: record.operation.ruleID))
            } catch { report.failed += 1; report.issues.append(error.localizedDescription) }
        }
        var options = ScanOptions(); options.conflictPolicy = .skip
        let plan = TidyPlan(id: report.runID, sourceRoot: original.plan.destinationRoot, destinationRoot: original.plan.sourceRoot, options: options, rules: [], operations: reverse, skips: [], createdAt: .now)
        if !reverse.isEmpty {
            let result = try await executeReserved(plan, undoOf: runID)
            report.moved += result.moved; report.failed += result.failed; report.cancelled = result.cancelled; report.issues += result.issues
            let records = try await journal.operations(runID: plan.id)
            for record in records where record.state == .completed { if let oldID = record.undoOf { try await journal.markRestored(operationID: oldID) } }
        } else if !original.removedDirectories.isEmpty {
            _ = try await journal.prepare(plan: plan)
            try await journal.markUndo(runID: plan.id, originalRunID: runID)
        }
        if !original.removedDirectories.isEmpty && !report.cancelled {
            var ownedDirectories: [URL: FileIdentity] = [:]
            for run in try await journal.runs() where run.undoOfRun == runID {
                for directory in run.directories { ownedDirectories[PathSafety.canonical(directory.url)] = directory.identity }
            }
            var restoredDirectories: [DirectoryBackup] = []
            for directory in original.removedDirectories.sorted(by: { $0.url.pathComponents.count < $1.url.pathComponents.count }) {
                do {
                    try PathSafety.validateDestination(root: original.plan.sourceRoot, path: directory.url)
                    if PathSafety.exists(directory.url) {
                        let current = try fileSystem.snapshot(at: directory.url)
                        guard current.metadata.kind == .directory,
                              current.fingerprint.identity == directory.identity || current.fingerprint.identity == ownedDirectories[PathSafety.canonical(directory.url)] else { throw TidyError.conflict(directory.url.path) }
                    } else { try await makeDirectories(directory.url, runID: plan.id) }
                    restoredDirectories.append(directory)
                } catch { report.failed += 1; report.issues.append(error.localizedDescription) }
            }
            for directory in restoredDirectories.reversed() {
                do {
                    for (name, data) in directory.attributes { try FileVerification.setAttribute(at: directory.url, name: name, data: data) }
                    try FileManager.default.setAttributes([.posixPermissions: Int(directory.mode), .creationDate: directory.createdAt, .modificationDate: directory.modifiedAt], ofItemAtPath: directory.url.path)
                } catch { report.failed += 1; report.issues.append(error.localizedDescription) }
            }
            if reverse.isEmpty { try await journal.finish(runID: plan.id, result: report) }
        }
        for directory in original.directories.sorted(by: { $0.url.pathComponents.count > $1.url.pathComponents.count }) where PathSafety.exists(directory.url) {
            if try fileSystem.snapshot(at: directory.url).fingerprint.identity == directory.identity { try? fileSystem.removeDirectoryIfEmpty(at: directory.url) }
        }
        try await journal.finishUndo(originalRunID: runID, result: report)
        emit(.finished(report)); return report
    }
    public func reconcile(runID: UUID) async throws -> RecoveryReport {
        var report = RecoveryReport()
        for op in try await journal.operations(runID: runID) {
            if op.state == .restored { report.restored += 1 }
            else if PathSafety.exists(op.operation.source.url) { report.retained += 1 }
            else if PathSafety.exists(op.operation.destination), try owned(fileSystem.snapshot(at: op.operation.destination), record: op) { report.retained += 1 }
            else { report.conflicts.append(op.operation.source.url.path) }
        }
        return report
    }
}
