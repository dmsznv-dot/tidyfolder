import Foundation
import Testing
@testable import TidyCore
struct BuiltinRulesTests {
    func destination(_ ext: String) -> String? {
        let m = FileMetadata(name: "file.\(ext)", fileExtension: ext, typeIdentifier: FileTypeClassifier.typeIdentifier(forExtension: ext) ?? "public.data", size: 1, createdAt: .now, modifiedAt: .now)
        return RuleEngine.match(metadata: m, rules: BuiltinRules.catalog(), now: .now)?.destination
    }
    @Test func categorizesCurrentDocumentedTypes() {
        for (ext, expected) in [("md", "Markdown"), ("epub", "eBooks"), ("obj", "3D Models"), ("eml", "Emails"), ("pdf", "PDFs"), ("png", "Images"), ("mov", "Movies"), ("mp3", "Audio"), ("xlsx", "Spreadsheets")] { #expect(destination(ext) == expected) }
        #expect(destination("unknownxyz") == "Unknown")
    }
    @Test func foldersAndAliasesDisabledByDefault() {
        let rules = BuiltinRules.catalog()
        #expect(rules.first { $0.destination == "Folders" }?.enabled == false)
        #expect(rules.first { $0.destination == "Aliases" }?.enabled == false)
        #expect(Set(rules.map(\.id)).count == rules.count)
        #expect(rules.map(\.id) == BuiltinRules.catalog().map(\.id))
    }
    @Test func allOnKeepsSpecialRulesOff() {
        let rules = BuiltinRules.settingEnabled(BuiltinRules.catalog(), enabled: true)
        #expect(rules.filter { $0.enabled }.count == rules.count - 2)
    }
}
