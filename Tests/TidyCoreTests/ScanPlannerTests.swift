import Foundation
import Testing
@testable import TidyCore
struct ScanPlannerTests {
    @Test func protectedApplicationStoreCannotBePlanned() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("source/AppData/history.sqlite"); try t.put("source/normal.pdf")
        var options = ScanOptions(); options.recursive = true
        let p = try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: options, now: .now, protectedURLs: [t.url("source/AppData")])
        #expect(p.operations.count == 1); #expect(p.operations.first?.source.url.lastPathComponent == "normal.pdf")
        await #expect(throws: Error.self) { try await ScanPlanner.plan(source: t.url("source/AppData"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: options, now: .now, protectedURLs: [t.url("source/AppData")]) }
    }

    @Test(arguments: [true, false]) func workingTreesAreProtected(markerIsDirectory: Bool) async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("repo/main.swift")
        if markerIsDirectory { try FileManager.default.createDirectory(at: t.url("repo/.git"), withIntermediateDirectories: true) }
        else { try t.put("repo/.git", "gitdir: ../actual") }
        var options = ScanOptions(); options.recursive = true
        let p = try await ScanPlanner.plan(source: t.root, destination: t.url("out"), rules: BuiltinRules.catalog(), options: options, now: .now)
        #expect(p.operations.isEmpty)
    }
    @Test func sparseBundleIsOpaqueByDefault() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("Archive.sparsebundle/Info.plist"); try t.put("Archive.sparsebundle/bands/0")
        var options = ScanOptions(); options.recursive = true
        let p = try await ScanPlanner.plan(source: t.root, destination: t.url("out"), rules: BuiltinRules.catalog(), options: options, now: .now)
        #expect(!p.operations.contains { $0.source.url.path.contains(".sparsebundle/") })
    }
    @Test func packageContentsRequireExplicitOptIn() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("App.app/Contents/inner.pdf")
        var options = ScanOptions(); options.recursive = true; options.skipBundles = false
        let p = try await ScanPlanner.plan(source: t.root, destination: t.url("out"), rules: BuiltinRules.catalog(), options: options, now: .now)
        #expect(p.operations.contains { $0.source.url.lastPathComponent == "inner.pdf" })
    }

    @Test func previewDoesNotMutate() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let input = try t.put("source/a.pdf", "original")
        try FileManager.default.createDirectory(at: t.url("out"), withIntermediateDirectories: true)
        let p = try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: BuiltinRules.catalog(), options: .init(), now: .now)
        #expect(p.operations.count == 1); #expect(p.operations.first?.destination.path == t.url("out/PDFs/a.pdf").path)
        #expect(try String(contentsOf: input, encoding: .utf8) == "original"); #expect(try FileManager.default.contentsOfDirectory(atPath: t.url("out").path).isEmpty)
    }
    @Test func excludesNestedDestination() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("a.pdf"); try t.put("out/already.pdf")
        var options = ScanOptions(); options.recursive = true
        let p = try await ScanPlanner.plan(source: t.root, destination: t.url("out"), rules: BuiltinRules.catalog(), options: options, now: .now)
        #expect(p.operations.count == 1)
    }
    @Test func sameRootExcludesOutputFolders() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("a.pdf"); try t.put("PDFs/already.pdf")
        var o = ScanOptions(); o.recursive = true
        let p = try await ScanPlanner.plan(source: t.root, destination: t.root, rules: BuiltinRules.catalog(), options: o, now: .now)
        #expect(p.operations.count == 1)
    }
    @Test func neverFollowsSymlinkCycle() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("a.pdf"); try FileManager.default.createSymbolicLink(at: t.url("loop"), withDestinationURL: t.root)
        var o = ScanOptions(); o.recursive = true
        let p = try await ScanPlanner.plan(source: t.root, destination: t.url("out"), rules: BuiltinRules.catalog(), options: o, now: .now)
        #expect(p.operations.count == 1); #expect(p.skips.contains { $0.url.lastPathComponent == "loop" })
    }
    @Test func packagesOpaque() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("App.app/Contents/inner.pdf")
        var o = ScanOptions(); o.recursive = true
        let p = try await ScanPlanner.plan(source: t.root, destination: t.url("out"), rules: BuiltinRules.catalog(), options: o, now: .now)
        #expect(!p.operations.contains { $0.source.url.lastPathComponent == "inner.pdf" })
    }
    @Test func excludesSubtree() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("keep/a.pdf"); try t.put("b.pdf")
        var o = ScanOptions(); o.recursive = true; o.excludedURLs = [t.url("keep")]
        #expect(try await ScanPlanner.plan(source: t.root, destination: t.url("out"), rules: BuiltinRules.catalog(), options: o, now: .now).operations.count == 1)
    }
    @Test func rejectsTraversalDestination() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("a.pdf")
        let r = Rule(name: "Escape", destination: "../outside", group: .init(children: [.condition(.init(field: .fileExtension, comparison: .equals, value: "pdf"))]))
        await #expect(throws: Error.self) { try await ScanPlanner.plan(source: t.root, destination: t.url("out"), rules: [r], options: .init(), now: .now) }
    }
    @Test func reservesDuplicateNames() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("one/a.pdf"); try t.put("two/a.pdf")
        var o = ScanOptions(); o.recursive = true; o.conflictPolicy = .keepBoth
        let p = try await ScanPlanner.plan(source: t.root, destination: t.url("out"), rules: BuiltinRules.catalog(), options: o, now: .now)
        #expect(p.operations.count == 2); #expect(Set(p.operations.map { $0.destination.path }).count == 2)
    }
    @Test func datedRootUnique() async throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("a.pdf"); var o = ScanOptions(); o.datedRoot = true
        let a = try await ScanPlanner.plan(source: t.root, destination: t.url("out"), rules: BuiltinRules.catalog(), options: o, now: .now)
        let b = try await ScanPlanner.plan(source: t.root, destination: t.url("out"), rules: BuiltinRules.catalog(), options: o, now: .now)
        #expect(a.operations.first?.destination != b.operations.first?.destination)
    }
}
