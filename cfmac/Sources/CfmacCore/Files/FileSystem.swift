import Darwin
import Foundation

public enum Paths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser.path

    public static func inHome(_ relative: String) -> String { home + "/" + relative }

    /// Replaces the home prefix with `~` for display.
    public static func abbreviated(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// Read-only file system queries. Only names, sizes, dates and types are read; file
/// contents never are, and personal-data stores (`PrivacyGuard`) are never entered.
public enum DiskUsage {
    static let sizeKeys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]

    /// Allocated bytes of a file or folder tree. Symlinks are not followed and private
    /// stores are skipped. `isCancelled` is polled so long walks can stop early.
    public static func size(of path: String, isCancelled: @Sendable () -> Bool = { false }) -> Int64 {
        guard !PrivacyGuard.isPrivate(path) else { return 0 }
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: sizeKeys), values.isSymbolicLink != true else { return 0 }
        guard values.isDirectory == true else { return allocated(values) }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(sizeKeys), errorHandler: { _, _ in true }) else {
            return 0
        }
        var total: Int64 = 0
        var visited = 0
        while let child = walker.nextObject() as? URL {
            visited += 1
            if visited % 2000 == 0, isCancelled() { break }
            guard let childValues = try? child.resourceValues(forKeys: sizeKeys) else { continue }
            if childValues.isDirectory == true {
                if PrivacyGuard.isPrivate(child.path) { walker.skipDescendants() }
                continue
            }
            total += allocated(childValues)
        }
        return total
    }

    public static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path) || isSymlink(path)
    }

    public static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue && !isSymlink(path)
    }

    public static func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    /// Full paths of a folder's entries, excluding Finder metadata. Private stores are not listed.
    public static func children(of path: String) -> [String] {
        guard !PrivacyGuard.isPrivate(path) else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
            .filter { $0 != ".DS_Store" }
            .map { (path as NSString).appendingPathComponent($0) }
    }

    public static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func allocated(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}

public enum RemovalMode: Sendable {
    case moveToTrash
    case deletePermanently
}

public enum RemovalOutcome: Sendable, Equatable {
    /// `trashedAt` is where the item now lives in the Trash, for putting it back.
    case removed(RemovalMode, trashedAt: String?)
    case skipped(String)
    case failed(String)

    public var didRemove: Bool {
        if case .removed = self { return true }
        return false
    }
}

/// An item moved to the Trash that can be put back.
public struct RestorableItem: Codable, Hashable, Sendable {
    public let originalPath: String
    public let trashedPath: String
    public let size: Int64

    public init(originalPath: String, trashedPath: String, size: Int64) {
        self.originalPath = originalPath
        self.trashedPath = trashedPath
        self.size = size
    }
}

/// Removes items after `SafetyGuard` approves them.
public enum Remover {
    public static func remove(_ path: String, mode: RemovalMode, protected: Set<String>) -> RemovalOutcome {
        if let reason = SafetyGuard.check(path, protected: protected) { return .skipped(reason.rawValue) }
        guard DiskUsage.exists(path) else { return .skipped("Already gone") }
        let url = URL(fileURLWithPath: path)
        do {
            switch mode {
            case .moveToTrash:
                var trashed: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                return .removed(.moveToTrash, trashedAt: trashed?.path)
            case .deletePermanently:
                try FileManager.default.removeItem(at: url)
                return .removed(.deletePermanently, trashedAt: nil)
            }
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            return .failed("Not writable by your account")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Asks Finder to trash an item, which prompts for authorization when the item needs it.
    public static func trashWithFinder(_ path: String, protected: Set<String>) -> RemovalOutcome {
        if let reason = SafetyGuard.check(path, protected: protected) { return .skipped(reason.rawValue) }
        let script = "tell application \"Finder\" to delete (POSIX file \(Shell.appleScriptLiteral(path)) as alias)"
        let result = Shell.run("/usr/bin/osascript", ["-e", script])
        return result.succeeded ? .removed(.moveToTrash, trashedAt: nil) : .failed("No permission to remove this item")
    }

    /// Moves trashed items back where they came from. Items whose original location is
    /// taken again are left in the Trash. Returns the items that could not be restored.
    public static func putBack(_ items: [RestorableItem]) -> [RestorableItem] {
        items.filter { item in
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: item.trashedPath), !DiskUsage.exists(item.originalPath) else { return true }
            do {
                try fileManager.createDirectory(atPath: (item.originalPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try fileManager.moveItem(atPath: item.trashedPath, toPath: item.originalPath)
                return false
            } catch {
                return true
            }
        }
    }
}

public enum Permissions {
    /// Full Disk Access check: macOS refuses to open the permissions database without it.
    /// The file is opened and closed immediately; nothing is read.
    public static var hasFullDiskAccess: Bool {
        let descriptor = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }
}
