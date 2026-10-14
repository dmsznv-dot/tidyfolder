import Foundation
import Testing
@testable import TidyCore
struct SettingsTests {
    func sample() -> AppSettings { var s = AppSettings(); s.rules = [Rule(name: "Invoices", destination: "Work/Invoices", group: .init(children: [.condition(.init(field: .name, comparison: .contains, value: "invoice"))]))]; s.scanOptions.recursive = true; s.language = .ru; return s }
    @Test func roundTripAllPredicates() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let s = sample(); let store = SettingsStore(url: t.url("settings.json")); try await store.save(s)
        #expect(try await store.load() == s)
    }
    @Test func atomicSaveFailureKeepsPrevious() async throws {
        let t = try TestTree(); defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: t.root.path); t.cleanup() }
        let store = SettingsStore(url: t.url("settings.json")); try await store.save(sample()); let before = try Data(contentsOf: t.url("settings.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: t.root.path)
        await #expect(throws: Error.self) { try await store.save(AppSettings()) }
        #expect(try Data(contentsOf: t.url("settings.json")) == before)
    }
    @Test func rejectsFutureSchema() async throws {
        let t = try TestTree(); defer { t.cleanup() }; var s = sample(); s.schemaVersion = 999; try JSONEncoder().encode(s).write(to: t.url("settings.json"))
        await #expect(throws: TidyError.newerSchema) { try await SettingsStore(url: t.url("settings.json")).load() }
    }
    @Test func damagedSettingsDoesNotResetSilently() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let u = try t.put("settings.json", "damaged")
        await #expect(throws: Error.self) { try await SettingsStore(url: u).load() }
        #expect(try String(contentsOf: u, encoding: .utf8) == "damaged")
    }
    @Test func languageDoesNotRenameSavedDestinations() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let store = SettingsStore(url: t.url("settings.json")); var s = sample(); s.language = .en; try await store.save(s)
        #expect(try await store.load().rules.first?.destination == "Work/Invoices")
    }
    @Test func settingsJSONUsesStableIDs() async throws {
        let t = try TestTree(); defer { t.cleanup() }; let store = SettingsStore(url: t.url("settings.json")); let s = sample(); try await store.save(s)
        #expect(try await store.load().rules.first?.id == s.rules.first?.id)
    }
}
