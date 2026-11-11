import Foundation

public struct StartupItem: Identifiable, Hashable, Sendable {
    public enum Scope: String, Sendable {
        case userAgent = "User background service"
        case systemAgent = "System background agent"
        case systemDaemon = "System background service"
    }

    public var id: String { path }
    public let path: String
    public let label: String
    public let program: String?
    public let scope: Scope
    public let isLoaded: Bool
    public let isDisabled: Bool

    /// The program this item launches no longer exists.
    public var isBroken: Bool { program.map { !FileManager.default.fileExists(atPath: $0) } ?? false }
    /// Only the user's own agents can be changed without administrator rights.
    public var isManageable: Bool { scope == .userAgent }
    public var isApple: Bool { label.hasPrefix("com.apple.") }
}

public enum StartupItems {
    public static func discover() -> [StartupItem] {
        let loaded = Set(
            Shell.run("/bin/launchctl", ["list"]).output.split(separator: "\n").dropFirst().compactMap { line in
                line.split(separator: "\t").last.map(String.init)
            })
        let disabledReport = Shell.run("/bin/launchctl", ["print-disabled", "gui/\(getuid())"]).output
        let folders: [(String, StartupItem.Scope)] = [
            (Paths.inHome("Library/LaunchAgents"), .userAgent),
            ("/Library/LaunchAgents", .systemAgent),
            ("/Library/LaunchDaemons", .systemDaemon),
        ]
        var items: [StartupItem] = []
        for (folder, scope) in folders {
            for path in DiskUsage.children(of: folder) where path.hasSuffix(".plist") {
                guard let plist = NSDictionary(contentsOfFile: path) as? [String: Any] else { continue }
                let label = plist["Label"] as? String ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                let disabled =
                    (plist["Disabled"] as? Bool ?? false)
                    || disabledReport.contains("\"\(label)\" => disabled")
                    || disabledReport.contains("\"\(label)\" => true")
                items.append(
                    StartupItem(
                        path: path, label: label,
                        program: program.flatMap { $0.hasPrefix("/") ? $0 : nil },
                        scope: scope, isLoaded: loaded.contains(label), isDisabled: disabled
                    ))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Enables or disables one of the user's own agents.
    public static func setEnabled(_ item: StartupItem, _ enabled: Bool) {
        guard item.isManageable else { return }
        let domain = "gui/\(getuid())"
        if enabled {
            Shell.run("/bin/launchctl", ["enable", "\(domain)/\(item.label)"])
            Shell.run("/bin/launchctl", ["bootstrap", domain, item.path])
        } else {
            Shell.run("/bin/launchctl", ["bootout", domain, item.path])
            Shell.run("/bin/launchctl", ["disable", "\(domain)/\(item.label)"])
        }
    }

    /// Unloads one of the user's own agents and moves its plist to the Trash.
    public static func moveToTrash(_ item: StartupItem, protected: Set<String>) -> RemovalOutcome {
        guard item.isManageable else { return .skipped("Needs administrator rights") }
        Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", item.path])
        return Remover.remove(item.path, mode: .moveToTrash, protected: protected)
    }
}
