import Foundation
import Testing

@testable import CfmacCore

/// A scratch folder under the system temporary directory, removed when the test ends.
final class TemporaryFolder {
    let path: String

    init() throws {
        path = (NSTemporaryDirectory() as NSString).appendingPathComponent("cfmac-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(atPath: path) }

    @discardableResult
    func file(_ name: String, bytes: Int) throws -> String {
        let target = (path as NSString).appendingPathComponent(name)
        try FileManager.default.createDirectory(atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: target, contents: Data(count: bytes))
        return target
    }
}

@Suite("Safety guard")
struct SafetyGuardTests {
    let home = Paths.home

    @Test func blocksCriticalSystemPaths() {
        for path in ["/", "/System", "/System/Library/Caches", "/usr/bin", "/Library", "/Applications", "/private/var/db/x"] {
            #expect(SafetyGuard.check(path, protected: []) == .criticalSystemPath, "\(path)")
        }
    }

    @Test func blocksTopLevelHomeFolders() {
        for relative in ["", "Library", "Documents", "Library/Caches", "Library/Application Support", ".Trash"] {
            let path = relative.isEmpty ? home : home + "/" + relative
            #expect(SafetyGuard.check(path, protected: []) == .topLevelFolder, "\(path)")
        }
    }

    @Test func allowsCacheChildren() {
        #expect(SafetyGuard.check(home + "/Library/Caches/com.example.app", protected: []) == nil)
        #expect(SafetyGuard.check("/usr/local/var/cache/x", protected: []) == nil)
    }

    @Test func rejectsMalformedPaths() {
        #expect(SafetyGuard.check("", protected: []) == .emptyPath)
        #expect(SafetyGuard.check("Library/Caches", protected: []) == .notAbsolute)
        #expect(SafetyGuard.check(home + "/Library/Caches/../Mail", protected: []) == .traversal)
        #expect(SafetyGuard.check(home + "/Library/Caches/./x", protected: []) == .traversal)
        #expect(SafetyGuard.check(home + "/Library/Caches/a\nb", protected: []) == .controlCharacters)
    }

    @Test func protectsSensitiveData() {
        #expect(SafetyGuard.check(home + "/Library/Keychains/login.keychain-db", protected: []) == .protectedData)
        #expect(SafetyGuard.check(home + "/Library/Messages/chat.db", protected: []) == .protectedData)
    }

    @Test func honorsTheUserProtectedList() {
        let protected: Set<String> = [home + "/Library/Caches/keep"]
        #expect(SafetyGuard.check(home + "/Library/Caches/keep", protected: protected) == .userProtected)
        #expect(SafetyGuard.check(home + "/Library/Caches/keep/inner", protected: protected) == .userProtected)
        #expect(SafetyGuard.check(home + "/Library/Caches/keeper", protected: protected) == nil)
    }

    @Test func refusesPathsThroughSymlinks() throws {
        let folder = try TemporaryFolder()
        let real = try folder.file("real/data.bin", bytes: 10)
        let link = folder.path + "/link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: folder.path + "/real")
        #expect(SafetyGuard.check(link + "/data.bin", protected: []) == .symlinkedPath)
        // The system's own /var -> /private/var alias is not treated as a user symlink.
        #expect(SafetyGuard.check(real, protected: []) == nil)
        // A symlink itself may be removed.
        #expect(SafetyGuard.check(link, protected: []) == nil)
    }
}

@Suite("File system")
struct FileSystemTests {
    @Test func sizesFolderTrees() throws {
        let folder = try TemporaryFolder()
        try folder.file("a.bin", bytes: 200_000)
        try folder.file("nested/b.bin", bytes: 300_000)
        #expect(DiskUsage.size(of: folder.path) >= 500_000)
    }

    @Test func doesNotFollowSymlinks() throws {
        let folder = try TemporaryFolder()
        let target = try TemporaryFolder()
        try target.file("big.bin", bytes: 1_000_000)
        try FileManager.default.createSymbolicLink(atPath: folder.path + "/link", withDestinationPath: target.path)
        #expect(DiskUsage.size(of: folder.path) < 100_000)
    }

    @Test func removesApprovedItems() throws {
        let folder = try TemporaryFolder()
        let file = try folder.file("cache/x.bin", bytes: 10)
        #expect(Remover.remove(file, mode: .deletePermanently, protected: []) == .removed(.deletePermanently, trashedAt: nil))
        #expect(!FileManager.default.fileExists(atPath: file))
    }

    @Test func skipsMissingAndGuardedItems() throws {
        let folder = try TemporaryFolder()
        #expect(Remover.remove(folder.path + "/missing", mode: .deletePermanently, protected: []) == .skipped("Already gone"))
        #expect(Remover.remove("/System", mode: .deletePermanently, protected: []) == .skipped(GuardReason.criticalSystemPath.rawValue))
        let kept = try folder.file("kept.bin", bytes: 10)
        #expect(Remover.remove(kept, mode: .deletePermanently, protected: [kept]) == .skipped(GuardReason.userProtected.rawValue))
        #expect(FileManager.default.fileExists(atPath: kept))
    }

    @Test func abbreviatesHome() {
        #expect(Paths.abbreviated(Paths.home + "/Library") == "~/Library")
        #expect(Paths.abbreviated("/Applications") == "/Applications")
    }
}
