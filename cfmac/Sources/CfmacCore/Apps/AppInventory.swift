import CoreServices
import Foundation

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let bundleIdentifier: String
    public let version: String
    public let isIntelOnly: Bool
    public let isFromAppStore: Bool
    /// Security, VPN and device-management software removed only with its vendor's uninstaller.
    public let requiresVendorUninstaller: Bool
    public let lastUsed: Date?
    public let installed: Date?
    public var size: Int64 = 0
    public var dataSize: Int64 = 0
}

public struct Remnant: Identifiable, Hashable, Sendable {
    public enum Confidence: String, Sendable {
        case automatic = "Auto"
        case review = "Review"

        public var help: String {
            switch self {
            case .automatic: "Strong match, selected automatically"
            case .review: "May hold data you want to keep"
            }
        }
    }

    public var id: String { path }
    public let path: String
    public let kind: String
    public let evidence: String
    public let confidence: Confidence
    public let size: Int64
}

public enum AppInventory {
    static let vendorUninstallerPrefixes = [
        "com.cisco", "com.crowdstrike", "com.paloaltonetworks", "com.eset", "com.sophos", "com.microsoft.wdav",
        "com.symantec", "com.mcafee", "com.thousandeyes", "com.jamf", "com.kandji",
    ]

    /// Apps in /Applications and ~/Applications (one folder level deep). Apple apps are excluded.
    public static func discover() -> [InstalledApp] {
        let roots = ["/Applications", Paths.inHome("Applications")]
        var bundles: [String] = []
        for root in roots {
            for path in DiskUsage.children(of: root) {
                if path.hasSuffix(".app") {
                    bundles.append(path)
                } else if DiskUsage.isDirectory(path) {
                    bundles += DiskUsage.children(of: path).filter { $0.hasSuffix(".app") }
                }
            }
        }
        return bundles.compactMap(describe).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func describe(_ path: String) -> InstalledApp? {
        guard let bundle = Bundle(path: path), let identifier = bundle.bundleIdentifier, !identifier.hasPrefix("com.apple.") else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let fallbackName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? fallbackName
        let version = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String) ?? "–"
        let architectures = bundle.executableArchitectures?.map(\.intValue) ?? []
        let url = URL(fileURLWithPath: path)
        let added = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return InstalledApp(
            path: path,
            name: name.isEmpty ? fallbackName : name,
            bundleIdentifier: identifier,
            version: version,
            isIntelOnly: !architectures.isEmpty && !architectures.contains(NSBundleExecutableArchitectureARM64),
            isFromAppStore: FileManager.default.fileExists(atPath: path + "/Contents/_MASReceipt/receipt"),
            requiresVendorUninstaller: vendorUninstallerPrefixes.contains { identifier.lowercased().hasPrefix($0) },
            lastUsed: lastUsedDate(path),
            installed: added?.addedToDirectoryDate ?? added?.creationDate
        )
    }

    static func lastUsedDate(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    // MARK: Leftovers

    /// Data an app left in the user Library. Bundle-ID matches are automatic; name matches need review.
    public static func remnants(of app: InstalledApp, protected: Set<String>) -> [Remnant] {
        let library = Paths.inHome("Library/")
        let id = app.bundleIdentifier
        var found: [Remnant] = []
        func add(_ path: String, _ kind: String, _ evidence: String, _ confidence: Remnant.Confidence) {
            guard DiskUsage.exists(path), !found.contains(where: { $0.path == path }), SafetyGuard.check(path, protected: protected) == nil else { return }
            found.append(Remnant(path: path, kind: kind, evidence: evidence, confidence: confidence, size: DiskUsage.size(of: path)))
        }
        add(library + "Application Support/" + id, "App Support", "Bundle ID", .automatic)
        add(library + "Caches/" + id, "Cache", "Bundle ID", .automatic)
        add(library + "HTTPStorages/" + id, "HTTP Storage", "Bundle ID", .automatic)
        add(library + "HTTPStorages/" + id + ".binarycookies", "Cookies", "Bundle ID", .automatic)
        add(library + "WebKit/" + id, "WebKit Data", "Bundle ID", .automatic)
        add(library + "Preferences/" + id + ".plist", "Preferences", "Bundle ID", .automatic)
        add(library + "Saved Application State/" + id + ".savedState", "Saved State", "Bundle ID", .automatic)
        add(library + "Logs/" + id, "Logs", "Bundle ID", .automatic)
        add(library + "Application Scripts/" + id, "App Scripts", "Bundle ID", .automatic)
        add(library + "Cookies/" + id + ".binarycookies", "Cookies", "Bundle ID", .automatic)
        // Sandboxed apps keep user documents in their container.
        add(library + "Containers/" + id, "Container", "Bundle ID", .review)
        for path in DiskUsage.children(of: library + "LaunchAgents") where (path as NSString).lastPathComponent.hasPrefix(id) {
            add(path, "Launch Item", "Bundle ID", .automatic)
        }
        for path in DiskUsage.children(of: library + "Group Containers") where (path as NSString).lastPathComponent.hasSuffix("." + id) {
            add(path, "Group Container", "Group container", .review)
        }
        if app.name.count >= 4 {
            add(library + "Application Support/" + app.name, "App Support", "Name match", .review)
            add(library + "Caches/" + app.name, "Cache", "Name match", .review)
            add(library + "Logs/" + app.name, "Logs", "Name match", .review)
        }
        return found
    }

    /// Moves the app (unless kept) and the chosen leftovers to the Trash, returning a log.
    public static func uninstall(_ app: InstalledApp, keepApp: Bool, remnants: [Remnant], protected: Set<String>) -> [String] {
        var log: [String] = []
        if !keepApp {
            switch Remover.remove(app.path, mode: .moveToTrash, protected: protected) {
            case .removed:
                log.append("Moved \(app.name) to Trash")
            case .skipped(let reason):
                log.append("\(app.name): \(reason)")
            case .failed:
                // Root-owned bundles: Finder asks for authorization.
                let viaFinder = Remover.trashWithFinder(app.path, protected: protected)
                log.append(viaFinder.didRemove ? "Moved \(app.name) to Trash" : "No permission to remove \(app.name)")
            }
        }
        for remnant in remnants {
            switch Remover.remove(remnant.path, mode: .moveToTrash, protected: protected) {
            case .removed: log.append("Removed \(remnant.kind) · \(Format.bytes(remnant.size))")
            case .skipped(let reason), .failed(let reason): log.append("Kept \(remnant.kind): \(reason)")
            }
        }
        return log
    }
}
