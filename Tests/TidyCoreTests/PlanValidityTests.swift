import Foundation
import Testing
@testable import TidyCore
struct PlanValidityTests {
    func setup(_ t: TestTree) async throws -> (TidyPlan, AppSettings) {
        try t.put("source/a.pdf"); let s = AppSettings(); return (try await ScanPlanner.plan(source: t.url("source"), destination: t.url("out"), rules: s.rules, options: s.scanOptions, now: .now), s)
    }
    @Test func ruleEditInvalidatesPlan() async throws {
        let t = try TestTree(); defer { t.cleanup() }; var (p,s) = try await setup(t); s.rules[0].enabled.toggle()
        #expect(!PlanValidity.isCurrent(plan: p, settings: s, source: t.url("source"), destination: t.url("out")))
    }
    @Test func sourceChangeInvalidatesPlan() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let (p,s) = try await setup(t)
        #expect(!PlanValidity.isCurrent(plan: p, settings: s, source: t.url("other"), destination: t.url("out")))
    }
    @Test func optionChangeInvalidatesPlan() async throws {
        let t = try TestTree(); defer { t.cleanup() }; var (p,s) = try await setup(t)
        #expect(PlanValidity.isCurrent(plan: p, settings: s, source: t.url("source"), destination: t.url("out")))
        s.scanOptions.recursive.toggle(); #expect(!PlanValidity.isCurrent(plan: p, settings: s, source: t.url("source"), destination: t.url("out")))
    }
}
