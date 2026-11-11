import CoreServices
import Foundation

public enum CleanSection: String, CaseIterable, Identifiable, Sendable {
    case custom, system, app, browsers, communication, developer, design, ai, cloud, leftovers, trash, storage
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .custom: "Your Folders"
        case .system: "System Data"
        case .app: "App Caches & Logs"
        case .browsers: "Browsers"
        case .communication: "Communication"
        case .developer: "Developer Tools"
        case .design: "Design Tools"
        case .ai: "AI Tools"
        case .cloud: "Cloud Storage"
        case .leftovers: "Uninstalled App Leftovers"
        case .trash: "Trash"
        case .storage: "Manage Separately"
        }
    }

    public var detail: String {
        switch self {
        case .custom: "Folders you added. Nothing here is selected until you choose it"
        case .system: "System caches, crash reports and saved window states. Backups are untouched"
        case .app: "App caches plus old logs. Sign-ins and history are kept"
        case .browsers: "Browser caches. Cookies and sessions stay"
        case .communication: "Chat app caches. Old images and videos download again after cleaning"
        case .developer: "Caches of Xcode, SwiftPM, Node.js and other tools. The next build takes a little longer"
        case .design: "Design tool caches. Your project files are untouched"
        case .ai: "AI app caches. Conversations, projects and local models are kept"
        case .cloud: "Cloud sync caches. Re-syncs when accessed"
        case .leftovers: "Files left by deleted apps. Some may hold settings you want, so pick what to remove"
        case .trash: "Everything in the Trash. It can't be recovered once emptied"
        case .storage: "Shown for size only, cfmac won't clean these. Manage them in their app"
        }
    }

    public var symbol: String {
        switch self {
        case .custom: "folder.badge.person.crop"
        case .system: "gearshape.2"
        case .app: "square.stack.3d.up"
        case .browsers: "globe"
        case .communication: "bubble.left.and.bubble.right"
        case .developer: "hammer"
        case .design: "paintpalette"
        case .ai: "sparkles"
        case .cloud: "icloud"
        case .leftovers: "shippingbox"
        case .trash: "trash"
        case .storage: "externaldrive"
        }
    }
}

public enum Safety: String, Sendable {
    case safe = "Safe"
    case review = "Review"
    case manual = "Manual"

    public var help: String {
        switch self {
        case .safe: "Regenerable caches or logs, selected by default"
        case .review: "May hold app data or development files you still need"
        case .manual: "cfmac does not delete this. Manage it yourself"
        }
    }
}

/// A location that may be cleaned, before it is sized.
public struct CleanCandidate: Sendable, Equatable {
    public let path: String
    public let label: String
    public let detail: String
    public let section: CleanSection
    public let safety: Safety
    /// Bundle identifiers or app names whose running process should block cleaning.
    public var owners: [String] = []
    /// Remove the folder's children instead of the folder itself (Logs, Trash).
    public var contentsOnly = false
    /// Never moved to the Trash (the Trash itself).
    public var permanentOnly = false
}

/// Knows where cleanable data lives. Every query is read-only.
public enum CleanCatalog {
    private static func home(_ relative: String) -> String { Paths.inHome(relative) }

    /// Discovers every candidate, with nested duplicates removed.
    public static func discover(fullDiskAccess: Bool, customFolders: [CustomCleanFolder] = []) -> [CleanCandidate] {
        var candidates = customFolders.filter { DiskUsage.isDirectory($0.path) }.map(\.candidate)
        candidates += fixed() + chromiumCaches() + leftovers(fullDiskAccess: fullDiskAccess)
        candidates += userCaches(excluding: candidates.map(\.path))
        let paths = Set(candidates.map(\.path))
        return candidates.filter { candidate in
            !PrivacyGuard.isPrivate(candidate.path) && !paths.contains { $0 != candidate.path && candidate.path.hasPrefix($0 + "/") }
        }
    }

    static func fixed() -> [CleanCandidate] {
        let xcode = ["com.apple.dt.Xcode"]
        let list: [CleanCandidate] = [
            .init(path: home("Library/Logs"), label: "User Logs", detail: "Old app logs", section: .system, safety: .safe, contentsOnly: true),
            .init(
                path: home("Library/Saved Application State"), label: "Saved App States", detail: "Window positions apps restore on launch", section: .system,
                safety: .safe, contentsOnly: true),
            .init(
                path: home("Library/Caches/com.apple.QuickLook.thumbnailcache"), label: "QuickLook Thumbnails", detail: "macOS renders these again when needed",
                section: .system, safety: .safe),
            .init(
                path: home("Library/Developer/Xcode/DerivedData"), label: "Xcode DerivedData", detail: "Build products and indexes", section: .developer,
                safety: .safe, owners: xcode),
            .init(
                path: home("Library/Developer/Xcode/iOS DeviceSupport"), label: "iOS Device Support", detail: "Debug symbols for connected devices",
                section: .developer, safety: .review),
            .init(
                path: home("Library/Developer/Xcode/Archives"), label: "Xcode Archives", detail: "Archived builds, needed to symbolicate old releases",
                section: .developer, safety: .review),
            .init(
                path: home("Library/Developer/CoreSimulator/Caches"), label: "iOS Simulator Caches", detail: "Rebuilt when simulators boot",
                section: .developer, safety: .safe),
            .init(
                path: home("Library/Caches/com.apple.dt.Xcode"), label: "Xcode Cache", detail: "Rebuilt by Xcode", section: .developer, safety: .safe,
                owners: xcode),
            .init(
                path: home("Library/Caches/org.swift.swiftpm"), label: "SwiftPM Cache", detail: "Package checkouts download again", section: .developer,
                safety: .safe),
            .init(path: home(".npm/_cacache"), label: "npm Cache", detail: "Packages download again when needed", section: .developer, safety: .safe),
            .init(path: home(".npm/_npx"), label: "npx Cache", detail: "One-off package runs", section: .developer, safety: .safe),
            .init(path: home("Library/Caches/Yarn"), label: "Yarn Cache", detail: "Packages download again when needed", section: .developer, safety: .safe),
            .init(path: home(".cache/yarn"), label: "Yarn Cache", detail: "Packages download again", section: .developer, safety: .safe),
            .init(path: home("Library/Caches/pnpm"), label: "pnpm Cache", detail: "Metadata cache", section: .developer, safety: .safe),
            .init(path: home(".cache/pnpm"), label: "pnpm Cache", detail: "Packages download again", section: .developer, safety: .safe),
            .init(
                path: home("Library/pnpm/store"), label: "pnpm Store", detail: "Shared package store, projects relink on install", section: .developer,
                safety: .review),
            .init(path: home("Library/Caches/pip"), label: "pip Cache", detail: "Python wheels download again", section: .developer, safety: .safe),
            .init(path: home("Library/Caches/Homebrew"), label: "Homebrew Downloads", detail: "Old bottles and installers", section: .developer, safety: .safe),
            .init(path: home("Library/Caches/CocoaPods"), label: "CocoaPods Cache", detail: "Pods download again", section: .developer, safety: .safe),
            .init(path: home("Library/Caches/go-build"), label: "Go Build Cache", detail: "Rebuilt on next build", section: .developer, safety: .safe),
            .init(path: home(".cache/go-build"), label: "Go Build Cache", detail: "Rebuilt on next build", section: .developer, safety: .safe),
            .init(path: home(".gradle/caches"), label: "Gradle Caches", detail: "Dependencies download again", section: .developer, safety: .safe),
            .init(
                path: home(".cargo/registry/cache"), label: "Cargo Registry Cache", detail: "Crate archives download again", section: .developer, safety: .safe),
            .init(
                path: home("Library/Caches/ms-playwright"), label: "Playwright Browsers", detail: "Reinstall with playwright install", section: .developer,
                safety: .review),
            .init(path: home("Library/Caches/JetBrains"), label: "JetBrains Caches", detail: "IDE indexes rebuild on open", section: .developer, safety: .safe),
            .init(path: home(".cache/huggingface/hub"), label: "Hugging Face Hub", detail: "Downloaded models and datasets", section: .ai, safety: .review),
            .init(path: home(".cache/torch"), label: "PyTorch Cache", detail: "Downloaded weights", section: .ai, safety: .review),
            .init(path: home(".cache/whisper"), label: "Whisper Models", detail: "Downloaded speech models", section: .ai, safety: .review),
            .init(path: home(".cache/claude"), label: "Claude Cache", detail: "Tool cache", section: .ai, safety: .safe),
            .init(path: home(".cache/opencode"), label: "OpenCode Cache", detail: "Tool cache", section: .ai, safety: .safe),
            .init(path: home("Library/Caches/CloudKit"), label: "CloudKit Cache", detail: "Re-syncs when accessed", section: .cloud, safety: .safe),
            .init(path: home(".Trash"), label: "Trash", detail: "Empty permanently", section: .trash, safety: .review, contentsOnly: true, permanentOnly: true),
            .init(
                path: home("Library/Application Support/MobileSync/Backup"), label: "iPhone or iPad Backups", detail: "Manage in Finder › your device",
                section: .storage, safety: .manual),
            .init(path: home(".ollama/models"), label: "Ollama Models", detail: "Remove unused models with ollama rm", section: .storage, safety: .manual),
            .init(
                path: home(".cache/lm-studio/models"), label: "LM Studio Models", detail: "Remove unused models in LM Studio", section: .storage,
                safety: .manual),
            .init(
                path: home("Library/Containers/com.docker.docker/Data/vms"), label: "Docker Disk Image", detail: "Use docker system prune", section: .storage,
                safety: .manual),
            .init(
                path: home("Library/Developer/CoreSimulator/Devices"), label: "Simulator Devices", detail: "Delete unused simulators in Xcode",
                section: .storage, safety: .manual),
        ]
        return list.filter { DiskUsage.exists($0.path) }
    }

    // MARK: Chromium and Electron caches inside Application Support

    static let chromiumCacheFolders: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "GrShaderCache", "ShaderCache", "CachedData", "CachedExtensionVSIXs", "Crashpad",
    ]
    /// Profile data that is never walked into.
    static let keptFolders: Set<String> = ["IndexedDB", "Local Storage", "Session Storage", "databases", "Extensions", "node_modules"]
    /// Vendor folders whose children name the product (Google/Chrome).
    static let vendorFolders: Set<String> = ["Google", "Microsoft", "BraveSoftware", "Mozilla", "JetBrains", "Adobe"]

    static func chromiumCaches() -> [CleanCandidate] {
        let root = home("Library/Application Support")
        var found: [CleanCandidate] = []
        for top in DiskUsage.children(of: root) {
            let owner = (top as NSString).lastPathComponent
            guard !owner.hasPrefix("com.apple"), owner != "MobileSync", owner != "CloudDocs" else { continue }
            walk(top, root: root, depth: 0, owner: owner, into: &found)
        }
        return found
    }

    private static func walk(_ folder: String, root: String, depth: Int, owner: String, into found: inout [CleanCandidate]) {
        guard depth <= 3 else { return }
        for child in DiskUsage.children(of: folder) where DiskUsage.isDirectory(child) {
            let name = (child as NSString).lastPathComponent
            let owner = depth == 0 && vendorFolders.contains(owner) ? name : owner
            let section = section(forOwner: owner)
            if chromiumCacheFolders.contains(name) {
                let relative = String(child.dropFirst(root.count + 1))
                found.append(.init(path: child, label: "\(owner) \(name)", detail: relative, section: section, safety: .safe, owners: [owner]))
            } else if name == "Service Worker" {
                let storage = child + "/CacheStorage"
                if DiskUsage.exists(storage) {
                    found.append(
                        .init(
                            path: storage, label: "\(owner) Service Worker Cache", detail: "Offline web data, downloads again", section: section, safety: .safe,
                            owners: [owner]))
                }
            } else if !keptFolders.contains(name) {
                walk(child, root: root, depth: depth + 1, owner: owner, into: &found)
            }
        }
    }

    static let sectionKeywords: [(CleanSection, [String])] = [
        (.browsers, ["chrome", "chromium", "brave", "edge", "arc", "vivaldi", "opera", "firefox", "dia", "zen", "orion"]),
        (.communication, ["slack", "discord", "teams", "zoom", "whatsapp", "telegram", "signal", "skype", "wechat", "messenger", "mattermost", "element"]),
        (.ai, ["claude", "chatgpt", "openai", "cursor", "windsurf", "ollama", "lm studio", "perplexity", "copilot", "codex", "antigravity"]),
        (.design, ["figma", "sketch", "adobe", "canva", "framer", "blender", "affinity"]),
        (.developer, ["code", "vscode", "jetbrains", "postman", "docker", "github desktop", "insomnia", "zed", "sublime"]),
        (.cloud, ["dropbox", "google drive", "drivefs", "onedrive", "box", "notion"]),
    ]

    /// Classifies an owner name by whole-word keyword match.
    static func section(forOwner name: String) -> CleanSection {
        let words = Set(name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let lowered = name.lowercased()
        for (section, keywords) in sectionKeywords {
            if keywords.contains(where: { $0.contains(" ") ? lowered.contains($0) : words.contains($0) }) { return section }
        }
        return .app
    }

    // MARK: ~/Library/Caches entries not claimed by a specific rule

    static let cacheDenyList: Set<String> = [
        "com.apple.HomeKit", "com.apple.findmy.fmipcore", "com.apple.Safari.SafeBrowsing", "com.apple.containermanagerd",
        "com.apple.ap.adprivacyd", "CloudKit", "FamilyCircle", "com.apple.homed", "com.apple.passd", "com.apple.akd",
    ]

    static func userCaches(excluding claimed: [String]) -> [CleanCandidate] {
        DiskUsage.children(of: home("Library/Caches")).compactMap { path in
            let name = (path as NSString).lastPathComponent
            guard !cacheDenyList.contains(name),
                !claimed.contains(where: { $0 == path || $0.hasPrefix(path + "/") || path.hasPrefix($0 + "/") })
            else { return nil }
            let label = AppLookup.displayName(forBundleIdentifier: name) ?? name
            let section: CleanSection = name.hasPrefix("com.apple.") ? .system : section(forOwner: label)
            return CleanCandidate(path: path, label: label, detail: "~/Library/Caches/\(name)", section: section, safety: .safe, owners: [name])
        }
    }

    // MARK: Leftovers of apps that are no longer installed

    static func leftovers(fullDiskAccess: Bool) -> [CleanCandidate] {
        var found: [CleanCandidate] = []
        for path in DiskUsage.children(of: home("Library/Saved Application State")) {
            let id = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if AppLookup.looksLikeBundleIdentifier(id), !AppLookup.isInstalled(id) {
                found.append(.init(path: path, label: "Saved State · \(id)", detail: "Window state of a removed app", section: .leftovers, safety: .safe))
            }
        }
        for path in DiskUsage.children(of: home("Library/Preferences")) where path.hasSuffix(".plist") {
            let id = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if AppLookup.looksLikeBundleIdentifier(id), !AppLookup.isInstalled(id) {
                found.append(.init(path: path, label: "Preferences · \(id)", detail: "Settings of a removed app", section: .leftovers, safety: .review))
            }
        }
        // Reading other apps' containers needs Full Disk Access; without it macOS prompts per app.
        if fullDiskAccess {
            for path in DiskUsage.children(of: home("Library/Containers")) {
                let id = (path as NSString).lastPathComponent
                if AppLookup.looksLikeBundleIdentifier(id), !AppLookup.isInstalled(id) {
                    found.append(.init(path: path, label: "Container · \(id)", detail: "Sandbox data of a removed app", section: .leftovers, safety: .review))
                }
            }
        }
        return found
    }
}

/// Launch Services lookups, without AppKit.
public enum AppLookup {
    public static func applicationURL(forBundleIdentifier id: String) -> URL? {
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil)?.takeRetainedValue() as? [URL] else { return nil }
        return urls.first
    }

    /// True when the app, or the app an extension belongs to, is installed.
    public static func isInstalled(_ bundleIdentifier: String) -> Bool {
        var parts = bundleIdentifier.split(separator: ".")
        while parts.count >= 2 {
            if applicationURL(forBundleIdentifier: parts.joined(separator: ".")) != nil { return true }
            guard parts.count > 2 else { break }
            parts.removeLast()
        }
        return false
    }

    public static func displayName(forBundleIdentifier id: String) -> String? {
        guard id.contains("."), let url = applicationURL(forBundleIdentifier: id) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    public static func looksLikeBundleIdentifier(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 3 && parts.allSatisfy { !$0.isEmpty } && !text.hasPrefix("com.apple.") && !text.contains(" ")
    }
}
