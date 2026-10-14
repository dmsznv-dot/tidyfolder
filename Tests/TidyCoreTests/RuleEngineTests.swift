import Foundation
import Testing
@testable import TidyCore

struct RuleEngineTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var invoice: FileMetadata { FileMetadata(name: "Счёт-invoice.pdf", fileExtension: "pdf", typeIdentifier: "com.adobe.pdf", kind: .regularFile, size: 1024, createdAt: now, modifiedAt: now.addingTimeInterval(-86400), tags: ["Work"]) }
    func rule(_ condition: RuleCondition, folder: String = "Invoices") -> Rule { Rule(name: folder, destination: folder, group: RuleGroup(children: [.condition(condition)])) }

    @Test func firstEnabledMatchWins() {
        var disabled = rule(.init(field: .fileExtension, comparison: .equals, value: "pdf"), folder: "Disabled"); disabled.enabled = false
        let custom = rule(.init(field: .name, comparison: .contains, value: "invoice"))
        let generic = rule(.init(field: .fileExtension, comparison: .equals, value: "pdf"), folder: "PDFs")
        #expect(RuleEngine.match(metadata: invoice, rules: [disabled, custom, generic], now: now)?.ruleID == custom.id)
    }
    @Test func nestedNoneGroup() {
        let excluded = RuleGroup(mode: .none, children: [.condition(.init(field: .name, comparison: .contains, value: "draft"))])
        let r = Rule(name: "Final", destination: "Final", group: RuleGroup(children: [.group(excluded), .condition(.init(field: .fileExtension, comparison: .equals, value: "PDF"))]))
        #expect(RuleEngine.match(metadata: invoice, rules: [r], now: now)?.destination == "Final")
    }
    @Test func sizeBoundaryInclusive() {
        #expect(RuleEngine.match(metadata: invoice, rules: [rule(.init(field: .size, comparison: .atLeast, value: "1024"))], now: now) != nil)
        #expect(RuleEngine.match(metadata: invoice, rules: [rule(.init(field: .size, comparison: .greaterThan, value: "1024"))], now: now) == nil)
    }
    @Test func relativeDateUsesInjectedClock() {
        #expect(RuleEngine.match(metadata: invoice, rules: [rule(.init(field: .modifiedAt, comparison: .withinDays, value: "2"))], now: now) != nil)
        #expect(RuleEngine.match(metadata: invoice, rules: [rule(.init(field: .modifiedAt, comparison: .withinDays, value: "0"))], now: now) == nil)
    }
    @Test func unicodeNameComparison() {
        #expect(RuleEngine.match(metadata: invoice, rules: [rule(.init(field: .name, comparison: .beginsWith, value: "счёт"))], now: now) != nil)
    }
    @Test func codableRoundTrip() throws {
        let r = rule(.init(field: .tags, comparison: .contains, value: "Work"))
        let decoded = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(r))
        #expect(decoded == r)
        #expect(RuleEngine.match(metadata: invoice, rules: [decoded], now: now)?.destination == "Invoices")
    }
    @Test func emptyAndInvalidConditionsNeverMatch() {
        let empty = Rule(name: "Empty", destination: "Empty", group: .init(mode: .none, children: []))
        #expect(RuleEngine.match(metadata: invoice, rules: [empty, rule(.init(field: .size, comparison: .greaterThan, value: "abc"))], now: now) == nil)
    }
}
