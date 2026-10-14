import Foundation
import Darwin
import TidyCore
@main struct Harness {
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "--benchmark" {
            try await benchmark(base: URL(fileURLWithPath: args[2])); return
        }
        guard args.count >= 5 else { throw TidyError.io("Usage: TidyHarness source destination journal checkpoint") }
        let source = URL(fileURLWithPath: args[1]), destination = URL(fileURLWithPath: args[2]), db = URL(fileURLWithPath: args[3]), crash = args[4]
        let coordinator = ExecutionCoordinator(journal: try SQLiteJournal(url: db), checkpoint: { point, _ in if point.rawValue == crash { _exit(89) } })
        let summary: RunSummary
        if args.count > 5, args[5].hasPrefix("undo:"), let id = UUID(uuidString: String(args[5].dropFirst(5))) { summary = try await coordinator.undo(runID: id) }
        else {
            let plan = try await ScanPlanner.plan(source: source, destination: destination, rules: BuiltinRules.catalog(), options: .init(), now: .now)
            summary = try await coordinator.execute(plan: plan)
        }
        print("moved=\(summary.moved), failed=\(summary.failed)")
    }
    static func benchmark(base: URL) async throws {
        let root = base.appendingPathComponent("benchmark-" + UUID().uuidString)
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let bytes = Data(repeating: 65, count: 128)
        for n in 0..<10_000 { try bytes.write(to: source.appendingPathComponent("file-\(n).pdf")) }
        let start = Date()
        let plan = try await ScanPlanner.plan(source: source, destination: destination, rules: BuiltinRules.catalog(), options: .init(), now: .now)
        let previewSeconds = Date().timeIntervalSince(start)
        print("preview: \(plan.operations.count) files, \(previewSeconds) seconds"); fflush(stdout)
        guard plan.operations.count == 10_000 else { throw TidyError.io("Benchmark missed input files") }
        let runner = ExecutionCoordinator(journal: try SQLiteJournal(url: root.appendingPathComponent("history.sqlite")))
        let moveStart = Date(), result = try await runner.execute(plan: plan)
        print("sort: \(result.moved) files, \(Date().timeIntervalSince(moveStart)) seconds, failed \(result.failed)"); fflush(stdout)
        guard result.moved == 10_000, result.failed == 0 else { throw TidyError.io("Benchmark sort failed") }
        let undoStart = Date(), undo = try await runner.undo(runID: plan.id)
        print("undo: \(undo.moved) files, \(Date().timeIntervalSince(undoStart)) seconds, failed \(undo.failed)"); fflush(stdout)
        guard undo.moved == 10_000, undo.failed == 0 else { throw TidyError.io("Benchmark undo failed") }
        for n in 0..<10_000 { guard try Data(contentsOf: source.appendingPathComponent("file-\(n).pdf")) == bytes else { throw TidyError.io("Benchmark bytes changed") } }
        print("verified 10000 restored contents; fixture: \(root.path)")
    }
}
