import Foundation
import CryptoKit
import Darwin
public enum FileVerification {
    public static func attributes(at url: URL) throws -> [String: Data] {
        let count = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard count >= 0 else { throw TidyError.io("Unable to read attributes: \(url.path)") }
        if count == 0 { return [:] }
        var buffer = [CChar](repeating: 0, count: count)
        guard listxattr(url.path, &buffer, count, XATTR_NOFOLLOW) == count else { throw TidyError.changed(url.path) }
        let names = Data(buffer.map { UInt8(bitPattern: $0) }).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        var result: [String: Data] = [:]
        for name in names {
            let size = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard size >= 0 else { throw TidyError.changed(url.path) }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
            guard read == size else { throw TidyError.changed(url.path) }
            result[name] = data
        }
        return result
    }
    public static func setAttribute(at url: URL, name: String, data: Data) throws {
        let result = data.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
        guard result == 0 else { throw TidyError.io("Unable to write attribute \(name): \(url.path)") }
    }
    public static func digest(at root: URL) throws -> String {
        var hash = SHA256()
        func append(_ data: Data) { hash.update(data: Data("\(data.count):".utf8)); hash.update(data: data) }
        func visit(_ url: URL, _ relative: String) throws {
            let before = try SnapshotReader.read(url)
            append(Data(relative.utf8)); append(Data(before.metadata.kind.rawValue.utf8))
            var statValue = stat(); guard lstat(url.path, &statValue) == 0 else { throw TidyError.changed(url.path) }
            append(Data(String(statValue.st_mode & 0o7777).utf8))
            let attrs = try attributes(at: url)
            for name in attrs.keys.sorted() { append(Data(name.utf8)); append(attrs[name]!) }
            if before.isSymlink {
                append(Data(try FileManager.default.destinationOfSymbolicLink(atPath: url.path).utf8))
            } else if before.isDirectory {
                for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) { try visit(child, relative + "/" + child.lastPathComponent) }
            } else {
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                append(Data(String(before.metadata.size).utf8))
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
            }
            guard try SnapshotReader.read(url).fingerprint == before.fingerprint else { throw TidyError.changed(url.path) }
        }
        try visit(root, "")
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
