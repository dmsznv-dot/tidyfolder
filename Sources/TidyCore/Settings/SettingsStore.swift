import Foundation
public actor SettingsStore {
    let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> AppSettings {
        guard url.isFileURL else { throw TidyError.invalidPath(url.absoluteString) }
        guard PathSafety.exists(url) else { return AppSettings() }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 5_242_880 else { throw TidyError.io("Settings file is too large") }
        let result = try JSONDecoder().decode(AppSettings.self, from: data)
        try Self.validate(result); return result
    }
    public func save(_ settings: AppSettings) throws {
        guard url.isFileURL else { throw TidyError.invalidPath(url.absoluteString) }
        try Self.validate(settings)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    private static func validate(_ settings: AppSettings) throws {
        if settings.schemaVersion > 1 { throw TidyError.newerSchema }
        guard settings.schemaVersion == 1, settings.rules.count <= 500, Set(settings.rules.map(\.id)).count == settings.rules.count else { throw TidyError.io("Unsupported or invalid settings schema") }
        for rule in settings.rules {
            try PathSafety.validateRelative(rule.destination)
            guard RuleEngine.valid(rule.group) else { throw TidyError.invalidRule(rule.name) }
        }
    }
}
