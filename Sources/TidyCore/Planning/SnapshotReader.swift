import Foundation
import Darwin
public enum SnapshotReader {
    public static func read(_ url: URL) throws -> FileSnapshot {
        var s = stat()
        guard lstat(url.path, &s) == 0 else { throw TidyError.io("\(url.path): \(String(cString: strerror(errno)))") }
        let isLink = (s.st_mode & S_IFMT) == S_IFLNK
        func attribute(_ name: String) -> Data? {
            let size = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard size > 0, size < 1_048_576 else { return nil }
            var data = Data(count: size)
            let count = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
            return count == size ? data : nil
        }
        let tagData = attribute("com.apple.metadata:_kMDItemUserTags")
        let tags = tagData.flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String] }?.map { $0.components(separatedBy: "\n")[0] } ?? []
        let finderInfo = attribute("com.apple.FinderInfo")
        let alias = finderInfo.map { $0.count >= 10 && ($0[8] & 0x80) != 0 } ?? false
        let packageExtensions = ["app","framework","xcodeproj","xcworkspace","xcassets","pages","numbers","key","photoslibrary","bundle","playground","sparsebundle","band","rtfd","logicx","garageband","bandproject","imovielibrary","fcpbundle","photolibrary","aplibrary","dvdmedia","pkg","mpkg"]
        let directory = (s.st_mode & S_IFMT) == S_IFDIR
        guard [S_IFREG, S_IFDIR, S_IFLNK].contains(s.st_mode & S_IFMT) else { throw TidyError.unsupported(url.path) }
        let kind: FileKind = isLink ? .symlink : alias ? .alias : directory && packageExtensions.contains(url.pathExtension.lowercased()) ? .package : directory ? .directory : .regularFile
        let m = FileMetadata(name: url.lastPathComponent, fileExtension: url.pathExtension.lowercased(), typeIdentifier: FileTypeClassifier.typeIdentifier(forExtension: url.pathExtension) ?? "public.data", kind: kind, size: UInt64(max(0, s.st_size)), createdAt: Date(timeIntervalSince1970: Double(s.st_birthtimespec.tv_sec) + Double(s.st_birthtimespec.tv_nsec) / 1e9), modifiedAt: Date(timeIntervalSince1970: Double(s.st_mtimespec.tv_sec) + Double(s.st_mtimespec.tv_nsec) / 1e9), tags: tags)
        let fingerprint = FileFingerprint(identity: .init(device: UInt64(s.st_dev), inode: UInt64(s.st_ino)), size: m.size, modificationNanoseconds: Int64(s.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(s.st_mtimespec.tv_nsec))
        let unavailable = url.lastPathComponent.hasSuffix(".icloud") || (s.st_flags & UInt32(SF_DATALESS)) != 0
        return FileSnapshot(url: url, fingerprint: fingerprint, metadata: m, isUnavailable: unavailable)
    }
}
