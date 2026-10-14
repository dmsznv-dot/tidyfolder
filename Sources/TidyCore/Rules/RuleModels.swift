import Foundation

public enum FileKind: String, Codable, Sendable, CaseIterable { case regularFile, directory, package, alias, symlink }
public struct FileMetadata: Codable, Sendable, Equatable {
    public var name: String
    public var fileExtension: String
    public var typeIdentifier: String
    public var kind: FileKind
    public var size: UInt64
    public var createdAt: Date
    public var modifiedAt: Date
    public var tags: [String]
    public init(name: String, fileExtension: String, typeIdentifier: String, kind: FileKind = .regularFile, size: UInt64, createdAt: Date, modifiedAt: Date, tags: [String] = []) {
        self.name = name; self.fileExtension = fileExtension; self.typeIdentifier = typeIdentifier; self.kind = kind; self.size = size; self.createdAt = createdAt; self.modifiedAt = modifiedAt; self.tags = tags
    }
}
public struct RuleCondition: Codable, Sendable, Equatable {
    public enum Field: String, Codable, Sendable, CaseIterable { case name, fileExtension, type, kind, size, createdAt, modifiedAt, tags }
    public enum Comparison: String, Codable, Sendable, CaseIterable { case equals, notEquals, contains, notContains, beginsWith, endsWith, greaterThan, lessThan, atLeast, atMost, withinDays, olderThanDays }
    public var field: Field
    public var comparison: Comparison
    public var value: String
    public init(field: Field = .fileExtension, comparison: Comparison = .equals, value: String = "") { self.field = field; self.comparison = comparison; self.value = value }
}
public indirect enum RuleNode: Codable, Sendable, Equatable { case condition(RuleCondition), group(RuleGroup) }
public struct RuleGroup: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable, CaseIterable { case all, any, none }
    public var mode: Mode
    public var children: [RuleNode]
    public init(mode: Mode = .all, children: [RuleNode] = []) { self.mode = mode; self.children = children }
}
public struct Rule: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var destination: String
    public var group: RuleGroup
    public var builtin: Bool
    public init(id: UUID = UUID(), name: String, enabled: Bool = true, destination: String, group: RuleGroup, builtin: Bool = false) {
        self.id = id; self.name = name; self.enabled = enabled; self.destination = destination; self.group = group; self.builtin = builtin
    }
}
public struct RuleMatch: Sendable, Equatable { public let ruleID: UUID; public let destination: String }
