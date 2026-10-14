import Foundation
public struct VerificationEvidence: Codable, Sendable, Equatable { public var sourceFingerprint: FileFingerprint; public var digest: String }
public protocol FileSystem: Sendable {
    func snapshot(at: URL) throws -> FileSnapshot
    func renameExclusive(from: URL, to: URL) throws
    func copyExclusive(from: URL, to: URL) throws
    func verifyCopy(source: URL, copy: URL, expected: FileFingerprint) throws -> VerificationEvidence
    func synchronize(at: URL) throws
    func removeSource(at: URL, expected: VerificationEvidence) throws
    func createDirectoryExclusive(at: URL) throws
    func removeDirectoryIfEmpty(at: URL) throws
}
