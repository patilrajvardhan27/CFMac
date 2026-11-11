import Foundation

/// Why a maintenance task did not run.
public struct TaskSkipped: Error, Sendable, Equatable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }

    static let notNeeded = TaskSkipped("System state is normal")
    static let unavailable = TaskSkipped("Could not complete this task right now")
}

public struct OptimizeTask: Identifiable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case launchSpeed = "Launch speed"
        case databases = "System databases"
        case networkSearch = "Network & search"
        case maintenance = "System maintenance"

        public var runningTitle: String {
            switch self {
            case .launchSpeed: "Speeding up launches"
            case .databases: "Tidying databases"
            case .networkSearch: "Optimizing network & search"
            case .maintenance: "Maintaining the system"
            }
        }
    }

    public enum Work: Sendable {
        /// Runs as the user. Returns an optional detail line, or throws `TaskSkipped`.
        case user(@Sendable () throws -> String?)
        /// A shell command run as root; all such tasks share one administrator prompt.
        case administrator(script: String)
    }

    public let id: String
    public let title: String
    public let group: Group
    public let work: Work

    public var needsAdministrator: Bool {
        if case .administrator = work { return true }
        return false
    }
}

public enum OptimizeCatalog {
    public static func tasks(protected: Set<String>) -> [OptimizeTask] {
        [
            OptimizeTask(
                id: "quicklook", title: "Rebuild QuickLook cache", group: .launchSpeed,
                work: .user {
                    guard Shell.run("/usr/bin/qlmanage", ["-r", "cache"]).succeeded else { throw TaskSkipped("qlmanage is not available on this Mac") }
                    Shell.run("/usr/bin/qlmanage", ["-r"])
                    return "Thumbnail cache reset"
                }),
            OptimizeTask(
                id: "savedstate", title: "Clear old saved window states", group: .launchSpeed,
                work: .user {
                    let cutoff = Date().addingTimeInterval(-7 * 86_400)
                    let old = DiskUsage.children(of: Paths.inHome("Library/Saved Application State"))
                        .filter { (DiskUsage.modificationDate($0) ?? Date()) < cutoff }
                    guard !old.isEmpty else { throw TaskSkipped.notNeeded }
                    let removed = old.filter { Remover.remove($0, mode: .moveToTrash, protected: protected).didRemove }
                    return "\(removed.count) states older than 7 days"
                }),
            OptimizeTask(
                id: "brokenagents", title: "Remove broken background services", group: .launchSpeed,
                work: .user {
                    let broken = StartupItems.discover().filter { $0.isManageable && $0.isBroken }
                    guard !broken.isEmpty else { throw TaskSkipped.notNeeded }
                    broken.forEach { _ = StartupItems.moveToTrash($0, protected: protected) }
                    return broken.map(\.label).joined(separator: ", ")
                }),
            OptimizeTask(
                id: "preferences", title: "Repair corrupted preference files", group: .databases,
                work: .user {
                    let corrupted = DiskUsage.children(of: Paths.inHome("Library/Preferences"))
                        .filter { $0.hasSuffix(".plist") && !Shell.run("/usr/bin/plutil", ["-lint", "-s", $0], timeout: 5).succeeded }
                    guard !corrupted.isEmpty else { throw TaskSkipped.notNeeded }
                    let removed = corrupted.filter { Remover.remove($0, mode: .moveToTrash, protected: protected).didRemove }
                    return "Moved \(removed.count) unreadable files to Trash"
                }),
            OptimizeTask(
                id: "quarantine", title: "Clear download quarantine history", group: .databases,
                work: .user {
                    let database = Paths.inHome("Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")
                    guard DiskUsage.exists(database) else { throw TaskSkipped.notNeeded }
                    guard Shell.run("/usr/bin/sqlite3", [database, "DELETE FROM LSQuarantineEvent; VACUUM;"]).succeeded else { throw TaskSkipped.unavailable }
                    return nil
                }),
            OptimizeTask(
                id: "dns", title: "Flush DNS cache", group: .networkSearch,
                work: .administrator(script: "dscacheutil -flushcache; killall -HUP mDNSResponder")),
            OptimizeTask(
                id: "purge", title: "Purge inactive physical memory", group: .maintenance,
                work: .administrator(script: "purge")),
            OptimizeTask(
                id: "periodic", title: "Run periodic system maintenance", group: .maintenance,
                work: .administrator(script: "periodic daily weekly monthly")),
        ]
    }

    /// One script for every chosen administrator task, so the user sees a single prompt.
    /// Each task's exit status is echoed so the caller can report per-task results.
    public static func administratorScript(for tasks: [OptimizeTask]) -> String {
        tasks.compactMap { task -> String? in
            guard case .administrator(let script) = task.work else { return nil }
            return "if ( \(script) ) >/dev/null 2>&1; then echo \"\(task.id)=0\"; else echo \"\(task.id)=1\"; fi"
        }.joined(separator: "\n")
    }

    /// Reads `id=status` lines printed by `administratorScript`.
    public static func administratorResults(_ output: String) -> [String: Bool] {
        var results: [String: Bool] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=")
            if parts.count == 2 { results[String(parts[0])] = parts[1] == "0" }
        }
        return results
    }
}

/// System processes that can be restarted to clear UI glitches.
public struct GlitchFix: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let process: String

    public static let all: [GlitchFix] = [
        GlitchFix(id: "dock", title: "Dock", process: "Dock"),
        GlitchFix(id: "finder", title: "Finder", process: "Finder"),
        GlitchFix(id: "notifications", title: "Notification Center", process: "NotificationCenter"),
        GlitchFix(id: "controlcenter", title: "Control Center", process: "ControlCenter"),
        GlitchFix(id: "spotlight", title: "Spotlight", process: "Spotlight"),
        GlitchFix(id: "input", title: "Input switching", process: "TextInputMenuAgent"),
    ]

    /// macOS relaunches these processes automatically after they quit.
    public func run() -> Bool {
        Shell.run("/usr/bin/killall", [process]).succeeded
    }
}
