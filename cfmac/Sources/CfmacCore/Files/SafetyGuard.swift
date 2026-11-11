import Foundation

/// Why a path must not be removed.
public enum GuardReason: String, Sendable, Equatable {
    case emptyPath = "Empty path"
    case notAbsolute = "Not an absolute path"
    case controlCharacters = "Path contains control characters"
    case traversal = "Path steps outside its own tree"
    case criticalSystemPath = "Critical system path, left alone"
    case protectedData = "Personal data, left alone"
    case topLevelFolder = "Top-level system or home folder"
    case symlinkedPath = "Not cleaning through a symbolic link"
    case userProtected = "On your protected list"
}

/// The single gate every removal passes through.
public enum SafetyGuard {
    private static let criticalPaths: Set<String> = [
        "/", "/System", "/bin", "/sbin", "/usr", "/etc", "/var", "/private", "/Library",
        "/Applications", "/Users", "/cores", "/dev", "/Volumes", "/opt", "/tmp",
    ]

    private static let criticalPrefixes = ["/System/", "/bin/", "/sbin/", "/private/var/db/", "/dev/"]

    /// Folders under the home directory that may hold removable children but never go themselves.
    private static let topLevelHomeFolders: Set<String> = [
        "", "Library", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public",
        "Applications", ".Trash", "Library/Caches", "Library/Application Support", "Library/Preferences",
        "Library/Containers", "Library/Group Containers", "Library/Logs", "Library/Mobile Documents",
        "Library/LaunchAgents", "Library/Saved Application State", "Library/Developer",
    ]

    /// Symlinks macOS itself ships at the root (`/var` → `/private/var`).
    private static let systemAliases: Set<String> = ["/var", "/tmp", "/etc"]

    /// Returns nil when `path` may be removed, otherwise the reason it is blocked.
    public static func check(_ path: String, home: String = Paths.home, protected: Set<String>) -> GuardReason? {
        guard !path.isEmpty else { return .emptyPath }
        guard path.hasPrefix("/") else { return .notAbsolute }
        guard !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return .controlCharacters }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("..") && !components.contains(".") else { return .traversal }

        let clean = (path as NSString).standardizingPath
        if criticalPaths.contains(clean) || criticalPrefixes.contains(where: clean.hasPrefix) { return .criticalSystemPath }
        if clean.hasPrefix("/usr/"), !clean.hasPrefix("/usr/local/") { return .criticalSystemPath }
        if PrivacyGuard.isPrivate(clean, home: home) { return .protectedData }
        if clean == home || clean.hasPrefix(home + "/") {
            let relative = String(clean.dropFirst(home.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if topLevelHomeFolders.contains(relative) { return .topLevelFolder }
        }
        if protected.contains(where: { clean == $0 || clean.hasPrefix($0 + "/") }) { return .userProtected }
        if hasSymlinkedAncestor(clean) { return .symlinkedPath }
        return nil
    }

    /// True when any folder above `path` is a symbolic link (the leaf itself may be one).
    static func hasSymlinkedAncestor(_ path: String) -> Bool {
        var prefix = ""
        for component in path.split(separator: "/").dropLast() {
            prefix += "/" + component
            if systemAliases.contains(prefix) { continue }
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: prefix)) != nil { return true }
        }
        return false
    }
}
