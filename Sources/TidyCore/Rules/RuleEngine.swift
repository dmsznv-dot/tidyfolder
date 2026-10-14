import Foundation
import UniformTypeIdentifiers
public enum RuleEngine {
    public static func match(metadata: FileMetadata, rules: [Rule], now: Date) -> RuleMatch? {
        for rule in rules where rule.enabled && valid(rule.group) {
            if evaluate(rule.group, metadata, now) { return RuleMatch(ruleID: rule.id, destination: rule.destination) }
        }
        return nil
    }
    public static func valid(_ group: RuleGroup, depth: Int = 0) -> Bool {
        guard depth < 32, !group.children.isEmpty, group.children.count <= 100 else { return false }
        return group.children.allSatisfy { node in
            switch node {
            case .group(let nested): return valid(nested, depth: depth + 1)
            case .condition(let c):
                guard !c.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                switch c.field {
                case .size: return UInt64(c.value) != nil && [.equals, .notEquals, .greaterThan, .lessThan, .atLeast, .atMost].contains(c.comparison)
                case .createdAt, .modifiedAt:
                    if [.withinDays, .olderThanDays].contains(c.comparison) { return Double(c.value).map { $0.isFinite && $0 >= 0 && $0 < 1_000_000 } ?? false }
                    return ISO8601DateFormatter().date(from: c.value) != nil && [.equals, .notEquals, .greaterThan, .lessThan, .atLeast, .atMost].contains(c.comparison)
                default: return [.equals, .notEquals, .contains, .notContains, .beginsWith, .endsWith].contains(c.comparison)
                }
            }
        }
    }
    private static func evaluate(_ group: RuleGroup, _ m: FileMetadata, _ now: Date) -> Bool {
        let results = group.children.map { node in
            switch node { case .condition(let c): return evaluate(c, m, now); case .group(let g): return evaluate(g, m, now) }
        }
        switch group.mode { case .all: return results.allSatisfy { $0 }; case .any: return results.contains(true); case .none: return !results.contains(true) }
    }
    private static func compare<T: Comparable>(_ a: T, _ b: T, _ op: RuleCondition.Comparison) -> Bool {
        switch op { case .equals: a == b; case .notEquals: a != b; case .greaterThan: a > b; case .lessThan: a < b; case .atLeast: a >= b; case .atMost: a <= b; default: false }
    }
    private static func text(_ a: String, _ b: String, _ op: RuleCondition.Comparison) -> Bool {
        let a = a.precomposedStringWithCanonicalMapping.lowercased(), b = b.precomposedStringWithCanonicalMapping.lowercased()
        switch op { case .equals: return a == b; case .notEquals: return a != b; case .contains: return a.contains(b); case .notContains: return !a.contains(b); case .beginsWith: return a.hasPrefix(b); case .endsWith: return a.hasSuffix(b); default: return false }
    }
    private static func evaluate(_ c: RuleCondition, _ m: FileMetadata, _ now: Date) -> Bool {
        switch c.field {
        case .name: return text(m.name, c.value, c.comparison)
        case .fileExtension: return text(m.fileExtension, c.value.trimmingCharacters(in: CharacterSet(charactersIn: ".")), c.comparison)
        case .kind: return text(m.kind.rawValue, c.value, c.comparison)
        case .type:
            let conforms = UTType(m.typeIdentifier).map { type in UTType(c.value).map { type.conforms(to: $0) } ?? false } ?? false
            if c.comparison == .equals { return conforms || text(m.typeIdentifier, c.value, .equals) }
            if c.comparison == .notEquals { return !conforms && text(m.typeIdentifier, c.value, .notEquals) }
            return text(m.typeIdentifier, c.value, c.comparison)
        case .tags:
            if [.notContains, .notEquals].contains(c.comparison) { return m.tags.allSatisfy { text($0, c.value, c.comparison) } }
            return m.tags.contains { text($0, c.value, c.comparison) }
        case .size: guard let value = UInt64(c.value) else { return false }; return compare(m.size, value, c.comparison)
        case .createdAt, .modifiedAt:
            let date = c.field == .createdAt ? m.createdAt : m.modifiedAt
            if let days = Double(c.value), [.withinDays, .olderThanDays].contains(c.comparison) {
                let age = now.timeIntervalSince(date)
                return c.comparison == .withinDays ? age >= 0 && age <= days * 86400 : age > days * 86400
            }
            guard let value = ISO8601DateFormatter().date(from: c.value) else { return false }
            return compare(date, value, c.comparison)
        }
    }
}
