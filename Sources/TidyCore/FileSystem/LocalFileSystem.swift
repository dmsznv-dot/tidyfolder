import Foundation
import Darwin
public struct LocalFileSystem: FileSystem {
    public init() {}
    public func snapshot(at: URL) throws -> FileSnapshot { try SnapshotReader.read(at) }
    private func failure(_ path: URL) -> TidyError {
        if errno == EEXIST { return .conflict(path.path) }
        if [ENOTSUP, EXDEV, EINVAL].contains(errno) { return .unsupported(path.path) }
        return .io("\(path.path): \(String(cString: strerror(errno)))")
    }
    public func renameExclusive(from: URL, to: URL) throws {
        guard renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 else { throw failure(to) }
    }
    public func copyExclusive(from: URL, to: URL) throws {
        guard copyfile(from.path, to.path, nil, UInt32(COPYFILE_ALL | COPYFILE_EXCL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC)) == 0 else { throw failure(to) }
    }
    public func verifyCopy(source: URL, copy: URL, expected: FileFingerprint) throws -> VerificationEvidence {
        guard try snapshot(at: source).fingerprint == expected else { throw TidyError.changed(source.path) }
        let a = try FileVerification.digest(at: source), b = try FileVerification.digest(at: copy)
        guard a == b, try snapshot(at: source).fingerprint == expected else { throw TidyError.changed(source.path) }
        return .init(sourceFingerprint: expected, digest: a)
    }
    public func synchronize(at url: URL) throws {
        let info = try snapshot(at: url)
        if info.isSymlink { return }
        if info.isDirectory {
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) { try synchronize(at: child) }
        }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure(url) }; defer { close(fd) }
        if fsync(fd) != 0 && !(info.isDirectory && errno == EINVAL) { throw failure(url) }
        if !info.isDirectory, fcntl(fd, F_FULLFSYNC) != 0 && ![ENOTSUP, EINVAL].contains(errno) { throw failure(url) }
    }
    public func removeSource(at url: URL, expected: VerificationEvidence) throws {
        guard try snapshot(at: url).fingerprint == expected.sourceFingerprint, try FileVerification.digest(at: url) == expected.digest else { throw TidyError.changed(url.path) }
        try FileManager.default.removeItem(at: url)
    }
    public func createDirectoryExclusive(at url: URL) throws { guard mkdir(url.path, 0o755) == 0 else { throw failure(url) } }
    public func removeDirectoryIfEmpty(at url: URL) throws { guard rmdir(url.path) == 0 else { throw failure(url) } }
}
