import Foundation
import Darwin
extension ExecutionCoordinator {
    func cleanupSource(_ plan: TidyPlan, result: inout RunSummary) async throws {
        let protected = [".git", ".svn", ".hg", ".build", ".superpowers"]
        let outputFolders = plan.rules.filter(\.enabled).map { plan.destinationRoot.appendingPathComponent($0.destination) }
        func collect(_ parent: URL) throws -> [URL] {
            if [".git", ".svn", ".hg"].contains(where: { PathSafety.exists(parent.appendingPathComponent($0)) }) { return [] }
            var dirs: [URL] = []
            for url in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
                if protectedURLs.contains(where: { PathSafety.contains($0, url) }) { continue }
                if url.lastPathComponent.hasPrefix(".") || plan.options.excludedURLs.contains(where: { PathSafety.contains($0, url) }) || outputFolders.contains(where: { PathSafety.contains($0, url) }) || (plan.sourceRoot != plan.destinationRoot && PathSafety.contains(plan.destinationRoot, url)) { continue }
                let snapshot = try fileSystem.snapshot(at: url)
                if snapshot.metadata.kind == .directory { if plan.options.recursive { dirs += try collect(url) }; dirs.append(url) }
            }
            return dirs
        }
        for dir in try collect(plan.sourceRoot) {
            if cancelled || Task.isCancelled { return }
            let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            guard contents.allSatisfy({ $0.lastPathComponent.hasPrefix(".") && !protected.contains($0.lastPathComponent) && !PathSafety.isLink($0) }) else { continue }
            let info = try fileSystem.snapshot(at: dir); var mode = stat(); guard lstat(dir.path, &mode) == 0 else { continue }
            let backup = DirectoryBackup(url: dir, identity: info.fingerprint.identity, attributes: try FileVerification.attributes(at: dir), mode: UInt16(mode.st_mode & 0o7777), createdAt: info.metadata.createdAt, modifiedAt: info.metadata.modifiedAt)
            try await journal.registerRemovedDirectory(runID: plan.id, directory: backup)
            let storage = plan.destinationRoot.appendingPathComponent(".tidyfolder-undo-\(plan.id.uuidString)/\(UUID().uuidString)")
            let operations = try contents.map { PlannedOperation(source: try fileSystem.snapshot(at: $0), destination: storage.appendingPathComponent($0.lastPathComponent), ruleID: UUID()) }
            try await journal.appendOperations(runID: plan.id, operations: operations)
            for op in operations { try PathSafety.validateDestination(root: plan.destinationRoot, path: op.destination); try await makeDirectories(op.destination.deletingLastPathComponent(), runID: plan.id); try await move(op, result: &result) }
            try fileSystem.removeDirectoryIfEmpty(at: dir)
        }
    }
}
