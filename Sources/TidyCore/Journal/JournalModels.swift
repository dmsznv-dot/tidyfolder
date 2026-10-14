import Foundation
public enum OperationState: String, Codable, Sendable { case prepared, copying, verified, publishIntent, committed, deleteIntent, sourceRemoved, completed, conflict, failed, restored }
public struct OperationEvidence: Codable, Sendable, Equatable {
    public var sourceDigest: String
    public var stagingURL: URL?
    public var destinationFingerprint: FileFingerprint?
    public var verification: VerificationEvidence?
    public var stagingFingerprint: FileFingerprint?
    public init(sourceDigest: String, stagingURL: URL? = nil, destinationFingerprint: FileFingerprint? = nil, verification: VerificationEvidence? = nil) { self.sourceDigest = sourceDigest; self.stagingURL = stagingURL; self.destinationFingerprint = destinationFingerprint; self.verification = verification }
}
public struct OperationRecord: Identifiable, Codable, Sendable {
    public var id: UUID { operation.id }
    public var runID: UUID
    public var operation: PlannedOperation
    public var state: OperationState
    public var evidence: OperationEvidence?
    public var issue: String?
    public var undoOf: UUID?
}
public struct OwnedDirectory: Codable, Sendable { public var url: URL; public var identity: FileIdentity }
public struct DirectoryBackup: Codable, Sendable { public var url: URL; public var identity: FileIdentity; public var attributes: [String: Data]; public var mode: UInt16; public var createdAt: Date; public var modifiedAt: Date }
public struct RunSummary: Codable, Sendable, Equatable {
    public var runID: UUID
    public var moved = 0
    public var copied = 0
    public var sourceRetained = 0
    public var skipped = 0
    public var failed = 0
    public var cancelled = false
    public var issues: [String] = []
    public init(runID: UUID) { self.runID = runID }
}
public struct RunRecord: Identifiable, Codable, Sendable {
    public var id: UUID
    public var plan: TidyPlan
    public var status: String
    public var summary: RunSummary?
    public var directories: [OwnedDirectory]
    public var undoOfRun: UUID?
    public var removedDirectories: [DirectoryBackup] = []
    public init(id: UUID, plan: TidyPlan, status: String, summary: RunSummary? = nil, directories: [OwnedDirectory] = [], undoOfRun: UUID? = nil, removedDirectories: [DirectoryBackup] = []) { self.id = id; self.plan = plan; self.status = status; self.summary = summary; self.directories = directories; self.undoOfRun = undoOfRun; self.removedDirectories = removedDirectories }
    enum CodingKeys: String, CodingKey { case id, plan, status, summary, directories, undoOfRun, removedDirectories }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); plan = try c.decode(TidyPlan.self, forKey: .plan); status = try c.decode(String.self, forKey: .status)
        summary = try c.decodeIfPresent(RunSummary.self, forKey: .summary); directories = try c.decodeIfPresent([OwnedDirectory].self, forKey: .directories) ?? []; undoOfRun = try c.decodeIfPresent(UUID.self, forKey: .undoOfRun); removedDirectories = try c.decodeIfPresent([DirectoryBackup].self, forKey: .removedDirectories) ?? []
    }
}
public protocol JournalStore: Sendable {
    func acquireRunLease() async throws -> RunLease
    func prepare(plan: TidyPlan) async throws -> RunRecord
    func transition(operationID: UUID, to: OperationState, evidence: OperationEvidence?) async throws
    func finish(runID: UUID, result: RunSummary) async throws
    func runs() async throws -> [RunRecord]
    func operations(runID: UUID) async throws -> [OperationRecord]
    func incompleteRuns() async throws -> [RunRecord]
    func registerDirectory(runID: UUID, directory: OwnedDirectory) async throws
    func finishUndo(originalRunID: UUID, result: RunSummary) async throws
    func markRestored(operationID: UUID) async throws
    func markUndo(runID: UUID, originalRunID: UUID) async throws
    func appendOperations(runID: UUID, operations: [PlannedOperation]) async throws
    func registerRemovedDirectory(runID: UUID, directory: DirectoryBackup) async throws
}
