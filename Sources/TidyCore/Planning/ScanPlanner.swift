import Foundation
public enum ScanPlanner {
    @concurrent public static func plan(source: URL, destination: URL, rules: [Rule], options: ScanOptions, now: Date, protectedURLs: [URL] = []) async throws -> TidyPlan {
        guard source.isFileURL, destination.isFileURL, !PathSafety.isLink(source), !PathSafety.isLink(destination) else { throw TidyError.invalidPath(source.path) }
        let source = source.standardizedFileURL, destination = destination.standardizedFileURL
        guard !protectedURLs.contains(where: { PathSafety.contains($0, source) || PathSafety.contains($0, destination) }) else { throw TidyError.invalidPath("Protected application storage") }
        let sourceInfo = try SnapshotReader.read(source)
        guard sourceInfo.isDirectory else { throw TidyError.invalidPath(source.path) }
        for rule in rules where rule.enabled {
            try PathSafety.validateRelative(rule.destination)
            guard RuleEngine.valid(rule.group) else { throw TidyError.invalidRule(rule.name) }
        }
        var result = TidyPlan(sourceRoot: source, destinationRoot: destination, options: options, rules: rules, operations: [], skips: [], createdAt: now)
        var output = destination
        if options.datedRoot {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
            output.appendPathComponent("\(source.lastPathComponent) \(formatter.string(from: now).replacingOccurrences(of: ":", with: "-")) \(result.id.uuidString.prefix(6))")
        }
        let outputFolders = rules.filter(\.enabled).map { output.appendingPathComponent($0.destination) }
        var reserved = Set<String>()
        func key(_ url: URL) -> String { url.path.precomposedStringWithCanonicalMapping.lowercased() }
        func skip(_ url: URL, _ reason: String) { result.skips.append(.init(url: url, reason: reason)) }
        func visit(_ directory: URL) throws {
            try Task.checkCancellation()
            if [".git", ".svn", ".hg"].contains(where: { PathSafety.exists(directory.appendingPathComponent($0)) }) { skip(directory, "Protected working tree"); return }
            let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
            for url in children {
                try Task.checkCancellation()
                if protectedURLs.contains(where: { PathSafety.contains($0, url) }) { skip(url, "Protected application storage"); continue }
                if options.excludedURLs.contains(where: { PathSafety.contains($0, url) }) { skip(url, "Excluded"); continue }
                if source != destination && PathSafety.contains(destination, url) { skip(url, "Destination folder"); continue }
                if outputFolders.contains(where: { PathSafety.contains($0, url) }) { skip(url, "Already organized"); continue }
                if [".git", ".svn", ".hg", ".superpowers", ".build"].contains(url.lastPathComponent) { skip(url, "Protected working folder"); continue }
                if url.lastPathComponent.hasPrefix(".") { skip(url, "Hidden item"); continue }
                let snapshot: FileSnapshot
                do { snapshot = try SnapshotReader.read(url) } catch { skip(url, error.localizedDescription); continue }
                if snapshot.isUnavailable { skip(url, "Cloud file is not downloaded"); continue }
                if snapshot.isSymlink { skip(url, "Symbolic link is not followed"); continue }
                if options.taggedPolicy == .skipTagged && !snapshot.metadata.tags.isEmpty || options.taggedPolicy == .onlyTagged && snapshot.metadata.tags.isEmpty { skip(url, "Finder tag policy"); continue }
                if snapshot.metadata.kind == .directory {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
                    if options.recursive && !contents.isEmpty { try visit(url); continue }
                    if !options.emptyFolders || !contents.isEmpty { skip(url, "Folder contents not included"); continue }
                }
                if snapshot.isPackage && options.recursive && !options.skipBundles { try visit(url); continue }
                guard let match = RuleEngine.match(metadata: snapshot.metadata, rules: rules, now: now) else { skip(url, "No matching rule"); continue }
                var target = output.appendingPathComponent(match.destination).appendingPathComponent(url.lastPathComponent)
                guard !protectedURLs.contains(where: { PathSafety.contains($0, target) }) else { throw TidyError.invalidPath("Protected application storage") }
                try PathSafety.validateDestination(root: destination, path: target)
                if snapshot.isDirectory && PathSafety.contains(url, target) { throw TidyError.invalidPath(target.path) }
                let original = target; var suffix = 2
                while PathSafety.exists(target) || reserved.contains(key(target)) {
                    if options.conflictPolicy == .skip { skip(url, "Destination name conflict"); break }
                    let ext = original.pathExtension, stem = ext.isEmpty ? original.lastPathComponent : original.deletingPathExtension().lastPathComponent
                    target = original.deletingLastPathComponent().appendingPathComponent("\(stem) (\(suffix))\(ext.isEmpty ? "" : "." + ext)"); suffix += 1
                }
                if options.conflictPolicy == .skip && (PathSafety.exists(target) || reserved.contains(key(target))) { continue }
                reserved.insert(key(target)); result.operations.append(.init(source: snapshot, destination: target, ruleID: match.ruleID))
            }
        }
        try visit(source)
        return result
    }
}
