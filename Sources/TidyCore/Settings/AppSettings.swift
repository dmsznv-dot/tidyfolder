import Foundation
public struct AppSettings: Codable, Sendable, Equatable {
    public enum Language: String, Codable, Sendable, CaseIterable { case system, ru, en }
    public enum Appearance: String, Codable, Sendable, CaseIterable { case system, light, dark }
    public var schemaVersion = 1
    public var rules = BuiltinRules.catalog()
    public var scanOptions = ScanOptions()
    public var language = Language.system
    public var appearance = Appearance.system
    public var revealAfterRun = false
    public var hideOtherApps = false
    public var diagnosticLogging = false
    public var sourceURL: URL?
    public var destinationURL: URL?
    public init() {}
}
