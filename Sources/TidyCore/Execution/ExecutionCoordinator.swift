import Foundation
public enum ExecutionCheckpoint: String, Sendable, CaseIterable { case afterPrepare, beforePublish, afterPublish, afterCommit, afterCopy, afterVerify, beforeSourceRemoval, afterSourceRemoval, afterComplete }
public enum RunEvent: Sendable { case started(UUID, Int), progress(UUID, Int, Int, String), issue(UUID, String), finished(RunSummary) }
public actor ExecutionCoordinator {
    let fileSystem: any FileSystem
    let journal: any JournalStore
    let protectedURLs: [URL]
    let checkpoint: @Sendable (ExecutionCheckpoint, UUID) async throws -> Void
    var active = false
    var cancelled = false
    var listeners: [UUID: AsyncStream<RunEvent>.Continuation] = [:]
    public init(fileSystem: any FileSystem = LocalFileSystem(), journal: any JournalStore, protectedURLs: [URL] = [], checkpoint: @escaping @Sendable (ExecutionCheckpoint, UUID) async throws -> Void = { _, _ in }) { self.fileSystem = fileSystem; self.journal = journal; self.protectedURLs = protectedURLs; self.checkpoint = checkpoint }
    public func execute(plan: TidyPlan) async throws -> RunSummary {
        guard !active else { throw TidyError.busy }; active = true; cancelled = false
        defer { active = false }
        let lease = try await journal.acquireRunLease(); defer { withExtendedLifetime(lease) {} }
        return try await executeReserved(plan)
    }
    func executeReserved(_ plan: TidyPlan, undoOf: UUID? = nil) async throws -> RunSummary {
        guard !protectedURLs.contains(where: { root in
            PathSafety.contains(root, plan.sourceRoot) || PathSafety.contains(root, plan.destinationRoot) || plan.operations.contains { PathSafety.contains(root, $0.source.url) || PathSafety.contains(root, $0.destination) }
        }) else { throw TidyError.invalidPath("Protected application storage") }
        var result = RunSummary(runID: plan.id); result.skipped = plan.skips.count
        guard !plan.operations.isEmpty else { return result }
        _ = try await journal.prepare(plan: plan)
        if let undoOf { try await journal.markUndo(runID: plan.id, originalRunID: undoOf) }
        emit(.started(plan.id, plan.operations.count)); try await checkpoint(.afterPrepare, plan.id)
        for (index, operation) in plan.operations.enumerated() {
            if cancelled || Task.isCancelled { result.cancelled = true; break }
            do {
                try PathSafety.validateDestination(root: plan.sourceRoot, path: operation.source.url)
                guard try fileSystem.snapshot(at: operation.source.url).fingerprint == operation.source.fingerprint else { throw TidyError.changed(operation.source.url.path) }
                try PathSafety.validateDestination(root: plan.destinationRoot, path: operation.destination)
                try await makeDirectories(operation.destination.deletingLastPathComponent(), runID: plan.id)
                try PathSafety.validateDestination(root: plan.destinationRoot, path: operation.destination)
                try await move(operation, result: &result)
            } catch is CancellationError {
                result.cancelled = true; break
            } catch {
                result.failed += 1; result.issues.append("\(operation.source.url.lastPathComponent): \(error.localizedDescription)")
                let records = try await journal.operations(runID: plan.id)
                if let current = records.first(where: { $0.id == operation.id }), ![.completed,.sourceRemoved].contains(current.state) {
                    try await journal.transition(operationID: operation.id, to: .failed, evidence: nil)
                }
                emit(.issue(plan.id, error.localizedDescription))
            }
            emit(.progress(plan.id, index + 1, plan.operations.count, operation.source.url.lastPathComponent))
        }
        if !result.cancelled, plan.options.removeEmptyFolders, undoOf == nil { try await cleanupSource(plan, result: &result) }
        try await journal.finish(runID: plan.id, result: result); emit(.finished(result)); return result
    }
    func makeDirectories(_ url: URL, runID: UUID) async throws {
        if PathSafety.exists(url) { guard try fileSystem.snapshot(at: url).isDirectory, !PathSafety.isLink(url) else { throw TidyError.invalidPath(url.path) }; return }
        try await makeDirectories(url.deletingLastPathComponent(), runID: runID)
        try await journal.registerDirectory(runID: runID, directory: .init(url: url, identity: .init(device: 0, inode: 0)))
        try fileSystem.createDirectoryExclusive(at: url)
        try await journal.registerDirectory(runID: runID, directory: .init(url: url, identity: try fileSystem.snapshot(at: url).fingerprint.identity))
    }
    func move(_ op: PlannedOperation, result: inout RunSummary) async throws {
        let source = op.source.url, target = op.destination
        var evidence = OperationEvidence(sourceDigest: try FileVerification.digest(at: source))
        guard try fileSystem.snapshot(at: source).fingerprint == op.source.fingerprint else { throw TidyError.changed(source.path) }
        if op.removesVerifiedCopy == true {
            let retained = try fileSystem.snapshot(at: target)
            guard try FileVerification.digest(at: target) == evidence.sourceDigest else { throw TidyError.changed(target.path) }
            evidence.destinationFingerprint = retained.fingerprint
            try await journal.transition(operationID: op.id, to: .publishIntent, evidence: evidence)
            try await journal.transition(operationID: op.id, to: .committed, evidence: evidence)
            try await journal.transition(operationID: op.id, to: .deleteIntent, evidence: evidence); try await checkpoint(.beforeSourceRemoval, op.id)
            guard try fileSystem.snapshot(at: target).fingerprint == retained.fingerprint, try FileVerification.digest(at: target) == evidence.sourceDigest else { throw TidyError.changed(target.path) }
            try fileSystem.removeSource(at: source, expected: .init(sourceFingerprint: op.source.fingerprint, digest: evidence.sourceDigest)); try await checkpoint(.afterSourceRemoval, op.id)
            try await journal.transition(operationID: op.id, to: .sourceRemoved, evidence: evidence)
            try await journal.transition(operationID: op.id, to: .completed, evidence: evidence); result.moved += 1; return
        }
        let targetDevice = try fileSystem.snapshot(at: target.deletingLastPathComponent()).fingerprint.identity.device
        if targetDevice == op.source.fingerprint.identity.device {
            try await journal.transition(operationID: op.id, to: .publishIntent, evidence: evidence)
            try await checkpoint(.beforePublish, op.id)
            try fileSystem.renameExclusive(from: source, to: target)
            try await checkpoint(.afterPublish, op.id)
            evidence.destinationFingerprint = try fileSystem.snapshot(at: target).fingerprint
            try await journal.transition(operationID: op.id, to: .committed, evidence: evidence)
            try await checkpoint(.afterCommit, op.id)
            try await journal.transition(operationID: op.id, to: .completed, evidence: evidence)
            result.moved += 1
        } else {
            let staging = target.deletingLastPathComponent().appendingPathComponent(".tidyfolder-\(op.id.uuidString).partial")
            evidence.stagingURL = staging
            try await journal.transition(operationID: op.id, to: .copying, evidence: evidence)
            try fileSystem.copyExclusive(from: source, to: staging); try await checkpoint(.afterCopy, op.id)
            let verification = try fileSystem.verifyCopy(source: source, copy: staging, expected: op.source.fingerprint)
            guard verification.digest == evidence.sourceDigest else { throw TidyError.changed(source.path) }
            evidence.verification = verification; evidence.stagingFingerprint = try fileSystem.snapshot(at: staging).fingerprint; try fileSystem.synchronize(at: staging)
            try await journal.transition(operationID: op.id, to: .verified, evidence: evidence); try await checkpoint(.afterVerify, op.id)
            if cancelled || Task.isCancelled { throw CancellationError() }
            try await journal.transition(operationID: op.id, to: .publishIntent, evidence: evidence); try await checkpoint(.beforePublish, op.id)
            try fileSystem.renameExclusive(from: staging, to: target); try await checkpoint(.afterPublish, op.id)
            evidence.destinationFingerprint = try fileSystem.snapshot(at: target).fingerprint
            try await journal.transition(operationID: op.id, to: .committed, evidence: evidence); try await checkpoint(.afterCommit, op.id)
            result.copied += 1
            if cancelled || Task.isCancelled { result.sourceRetained += 1; result.cancelled = true }
            else {
                try await journal.transition(operationID: op.id, to: .deleteIntent, evidence: evidence); try await checkpoint(.beforeSourceRemoval, op.id)
                do {
                    let published = try fileSystem.snapshot(at: target)
                    guard !published.isSymlink, published.fingerprint == evidence.destinationFingerprint,
                          try FileVerification.digest(at: target) == verification.digest else { throw TidyError.changed(target.path) }
                    try fileSystem.removeSource(at: source, expected: verification)
                } catch { result.sourceRetained += 1; throw error }
                try await checkpoint(.afterSourceRemoval, op.id)
                try await journal.transition(operationID: op.id, to: .sourceRemoved, evidence: evidence); result.moved += 1
            }
            try await journal.transition(operationID: op.id, to: .completed, evidence: evidence)
        }
        try await checkpoint(.afterComplete, op.id)
    }
    public func cancel() { cancelled = true }
    public func events() -> AsyncStream<RunEvent> {
        let id = UUID(); let pair = AsyncStream<RunEvent>.makeStream(bufferingPolicy: .bufferingNewest(30)); listeners[id] = pair.continuation
        pair.continuation.onTermination = { _ in Task { await self.removeListener(id) } }
        return pair.stream
    }
    private func removeListener(_ id: UUID) { listeners[id] = nil }
    func emit(_ event: RunEvent) { for listener in listeners.values { listener.yield(event) } }
}
