import Foundation
import Darwin
public enum PathSafety {
    public static func canonical(_ url: URL) -> URL {
        var parent = url.standardizedFileURL
        var missing: [String] = []
        while !exists(parent) {
            let next = parent.deletingLastPathComponent()
            if next.path == parent.path { return url.standardizedFileURL }
            missing.append(parent.lastPathComponent); parent = next
        }
        guard let resolved = realpath(parent.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        var result = URL(fileURLWithPath: String(cString: resolved))
        for component in missing.reversed() { result.appendPathComponent(component) }
        return result
    }
    public static func contains(_ root: URL, _ child: URL) -> Bool {
        let r = canonical(root).pathComponents, c = canonical(child).pathComponents
        return c.count >= r.count && Array(c.prefix(r.count)) == r
    }
    public static func validateRelative(_ path: String) throws {
        let parts = path.components(separatedBy: "/")
        guard !path.hasPrefix("/"), !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else { throw TidyError.invalidPath(path) }
    }
    public static func isLink(_ url: URL) -> Bool {
        var s = stat(); return lstat(url.path, &s) == 0 && (s.st_mode & S_IFMT) == S_IFLNK
    }
    public static func exists(_ url: URL) -> Bool { var s = stat(); return lstat(url.path, &s) == 0 }
    public static func validateDestination(root: URL, path: URL) throws {
        guard root.isFileURL, path.isFileURL, contains(root, path) else { throw TidyError.invalidPath("outside selected root \(root.path): \(path.path)") }
        guard !isLink(root), !isLink(path) else { throw TidyError.invalidPath("linked endpoint: \(path.path)") }
        let selectedRoot = canonical(root).path
        var current = path.deletingLastPathComponent()
        while canonical(current).path != selectedRoot {
            if isLink(current) { throw TidyError.invalidPath(current.path) }
            if exists(current), try !SnapshotReader.read(current).isDirectory { throw TidyError.invalidPath(current.path) }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { throw TidyError.invalidPath("root boundary \(selectedRoot): \(path.path)") }
            current = parent
        }
    }
}
