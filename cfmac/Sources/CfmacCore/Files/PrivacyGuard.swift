import Foundation

/// Personal-data stores cfmac never looks inside, even with Full Disk Access.
///
/// cfmac works with file names, sizes and dates only. Libraries that hold photos, mail,
/// messages, contacts, calendars, browsing history or credentials are skipped entirely:
/// they are not listed, sized, scanned or removed.
public enum PrivacyGuard {
    /// Folders under the home directory that hold personal data.
    static let privateHomeFolders: [String] = [
        "Library/Accounts", "Library/Application Support/AddressBook", "Library/Application Support/CallHistoryDB",
        "Library/Application Support/CallHistoryTransactions", "Library/Application Support/com.apple.TCC",
        "Library/Application Support/FaceTime", "Library/Application Support/Knowledge", "Library/Assistant",
        "Library/Biome", "Library/Calendars", "Library/Cookies", "Library/Daemon Containers", "Library/DuetExpertCenter",
        "Library/HomeKit", "Library/IdentityServices", "Library/Keychains", "Library/Mail", "Library/Messages",
        "Library/Metadata/CoreSpotlight", "Library/PersonalizationPortrait", "Library/Photos", "Library/Reminders",
        "Library/Safari", "Library/Sharing", "Library/Suggestions", "Pictures/Photo Booth Library",
    ]

    /// Apple apps keep notes, health, photos and similar data in their containers.
    static let privateContainerPrefixes = [
        "Library/Containers/com.apple.", "Library/Group Containers/group.com.apple.", "Library/Group Containers/com.apple.",
    ]

    /// Library packages that hold personal media, wherever they are.
    static let privatePackageExtensions: Set<String> = ["photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary"]

    static let privateSystemFolders = ["/Library/Application Support/com.apple.TCC", "/private/var/db"]

    /// True when `path` is, or is inside, a personal-data store.
    public static func isPrivate(_ path: String, home: String = Paths.home) -> Bool {
        if path.split(separator: "/").contains(where: { privatePackageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
            return true
        }
        if privateSystemFolders.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        guard path.hasPrefix(home + "/") else { return false }
        let relative = String(path.dropFirst(home.count + 1))
        if privateContainerPrefixes.contains(where: relative.hasPrefix) { return true }
        return privateHomeFolders.contains { relative == $0 || relative.hasPrefix($0 + "/") }
    }
}
