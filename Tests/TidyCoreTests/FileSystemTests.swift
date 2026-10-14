import Foundation
import Testing
@testable import TidyCore
struct FileSystemTests {
    @Test func destinationRaceNeverReplaces() throws {
        let t = try TestTree(); defer { t.cleanup() }; let a = try t.put("a", "source"), b = try t.put("b", "existing")
        #expect(throws: Error.self) { try LocalFileSystem().renameExclusive(from: a, to: b) }
        #expect(try String(contentsOf: a, encoding: .utf8) == "source"); #expect(try String(contentsOf: b, encoding: .utf8) == "existing")
    }
    @Test func copyFailureKeepsSource() throws {
        let t = try TestTree(); defer { t.cleanup() }; let a = try t.put("a", "source"), b = try t.put("b", "existing")
        #expect(throws: Error.self) { try LocalFileSystem().copyExclusive(from: a, to: b) }
        #expect(try String(contentsOf: a, encoding: .utf8) == "source"); #expect(try String(contentsOf: b, encoding: .utf8) == "existing")
    }
    @Test func verificationRejectsModifiedSource() throws {
        let t = try TestTree(); defer { t.cleanup() }; let a = try t.put("a", "before"); let fs = LocalFileSystem(); let original = try fs.snapshot(at: a)
        try fs.copyExclusive(from: a, to: t.url("copy")); try Data("after".utf8).write(to: a)
        #expect(throws: Error.self) { try fs.verifyCopy(source: a, copy: t.url("copy"), expected: original.fingerprint) }
    }
    @Test func preservesTagsAndResourceFork() throws {
        let t = try TestTree(); defer { t.cleanup() }; let a = try t.put("a", "body"), b = t.url("copy")
        try FileVerification.setAttribute(at: a, name: "com.apple.ResourceFork", data: Data("resource".utf8))
        try FileVerification.setAttribute(at: a, name: "com.apple.metadata:_kMDItemUserTags", data: PropertyListSerialization.data(fromPropertyList: ["Work\n6"], format: .binary, options: 0))
        let fs = LocalFileSystem(); let original = try fs.snapshot(at: a); try fs.copyExclusive(from: a, to: b)
        #expect(try FileVerification.attributes(at: b)["com.apple.ResourceFork"] == Data("resource".utf8))
        #expect(try fs.verifyCopy(source: a, copy: b, expected: original.fingerprint).digest.isEmpty == false)
        #expect(try FileVerification.attributes(at: a) == FileVerification.attributes(at: b))
    }
    @Test func packageCopyVerifiesNestedContents() throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("thing.app/Contents/a", "nested"); let fs = LocalFileSystem(); let a = t.url("thing.app"), b = t.url("copy.app")
        let original = try fs.snapshot(at: a); try fs.copyExclusive(from: a, to: b)
        #expect(try fs.verifyCopy(source: a, copy: b, expected: original.fingerprint).digest.isEmpty == false)
        try Data("changed".utf8).write(to: b.appendingPathComponent("Contents/a"))
        #expect(throws: Error.self) { try fs.verifyCopy(source: a, copy: b, expected: original.fingerprint) }
    }
    @Test func sourceDeletionRequiresVerifiedEvidence() throws {
        let t = try TestTree(); defer { t.cleanup() }; let a = try t.put("a", "safe"), b = t.url("copy"); let fs = LocalFileSystem(); let initial = try fs.snapshot(at: a)
        try fs.copyExclusive(from: a, to: b); let evidence = try fs.verifyCopy(source: a, copy: b, expected: initial.fingerprint)
        try Data("new edit".utf8).write(to: a)
        #expect(throws: Error.self) { try fs.removeSource(at: a, expected: evidence) }
        #expect(PathSafety.exists(a))
    }
    @Test func removesOnlyEmptyDirectories() throws {
        let t = try TestTree(); defer { t.cleanup() }; try t.put("folder/hidden", "keep")
        #expect(throws: Error.self) { try LocalFileSystem().removeDirectoryIfEmpty(at: t.url("folder")) }
        #expect(PathSafety.exists(t.url("folder/hidden")))
    }
}
