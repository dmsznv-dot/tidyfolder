import Foundation
struct TestTree {
    let root: URL
    init() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("TidyFolderTests-\(UUID())", isDirectory: true); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }
    @discardableResult func put(_ relative: String, _ text: String = "fixture") throws -> URL {
        let u = url(relative); try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(text.utf8).write(to: u); return u
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
