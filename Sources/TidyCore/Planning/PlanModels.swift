import Foundation
public struct FileIdentity: Codable, Sendable, Equatable { public var device: UInt64; public var inode: UInt64 }
public struct FileFingerprint: Codable, Sendable, Equatable { public var identity: FileIdentity; public var size: UInt64; public var modificationNanoseconds: Int64 }
public struct FileSnapshot: Codable, Sendable, Equatable {
    public var url: URL
    public var fingerprint: FileFingerprint
    public var metadata: FileMetadata
    public var isUnavailable: Bool
    public var isDirectory: Bool { metadata.kind == .directory || metadata.kind == .package }
    public var isPackage: Bool { metadata.kind == .package }
    public var isSymlink: Bool { metadata.kind == .symlink }
    public var isAlias: Bool { metadata.kind == .alias }
}
public struct ScanOptions: Codable, Sendable, Equatable {
    public enum TaggedPolicy: String, Codable, Sendable, CaseIterable { case includeAll, skipTagged, onlyTagged }
    public enum ConflictPolicy: String, Codable, Sendable, CaseIterable { case skip, keepBoth }
    public var recursive = false
    public var taggedPolicy = TaggedPolicy.includeAll
    public var emptyFolders = false
    public var skipBundles = true
    public var removeEmptyFolders = false
    public var datedRoot = false
    public var excludedURLs: [URL] = []
    public var conflictPolicy = ConflictPolicy.skip
    public init() {}
}
public struct PlannedOperation: Identifiable, Codable, Sendable, Equatable {
    public var id = UUID()
    public var source: FileSnapshot
    public var destination: URL
    public var ruleID: UUID
    public var removesVerifiedCopy: Bool? = nil
}
public struct SkipRecord: Identifiable, Codable, Sendable, Equatable {
    public var id = UUID()
    public var url: URL
    public var reason: String
}
public struct TidyPlan: Identifiable, Codable, Sendable, Equatable {
    public var id = UUID()
    public var sourceRoot: URL
    public var destinationRoot: URL
    public var options: ScanOptions
    public var rules: [Rule]
    public var operations: [PlannedOperation]
    public var skips: [SkipRecord]
    public var createdAt: Date
}
public enum TidyError: Error, LocalizedError, Sendable, Equatable {
    case invalidPath(String), conflict(String), changed(String), unsupported(String), io(String), busy, newerSchema, invalidRule(String), cancelled
    public var errorDescription: String? {
        switch self { case .invalidPath(let p): "Unsafe folder path: \(p)"; case .conflict(let p): "A file already exists: \(p)"; case .changed(let p): "File changed since preview: \(p)"; case .unsupported(let p): "Unsupported operation: \(p)"; case .io(let p): p; case .busy: "Another operation is running"; case .newerSchema: "This data comes from a newer version of TidyFolder"; case .invalidRule(let s): "Invalid rule: \(s)"; case .cancelled: "Operation cancelled" }
    }
}
