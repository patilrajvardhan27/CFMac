import Foundation

public struct AppUpdate: Identifiable, Hashable, Sendable {
    public enum Source: String, Sendable {
        case formula = "Homebrew"
        case cask = "Homebrew Cask"
        case appStore = "App Store"

        public var symbol: String {
            switch self {
            case .formula: "shippingbox"
            case .cask: "macwindow"
            case .appStore: "bag"
            }
        }
    }

    public var id: String { source.rawValue + "/" + name }
    public let name: String
    public let installedVersion: String
    public let latestVersion: String
    public let source: Source
    public let appStoreIdentifier: String?
}

public struct UpdateCheck: Sendable {
    public let updates: [AppUpdate]
    public let note: String?
}

public enum Updates {
    public static func check() -> UpdateCheck {
        var updates: [AppUpdate] = []
        var notes: [String] = []
        if let brew = Shell.homebrew {
            let result = Shell.run(brew, ["outdated", "--json=v2", "--greedy-auto-updates"], timeout: 120)
            if let parsed = parseHomebrew(result.output) {
                updates += parsed
            } else if !result.succeeded {
                notes.append("Homebrew check failed: \(result.error.prefix(160))")
            }
        } else {
            notes.append("Homebrew is not installed, so only App Store apps are checked.")
        }
        if let mas = Shell.appStoreCLI {
            updates += parseAppStore(Shell.run(mas, ["outdated"], timeout: 60).output)
        }
        return UpdateCheck(updates: updates, note: notes.isEmpty ? nil : notes.joined(separator: " "))
    }

    /// Parses `brew outdated --json=v2`.
    static func parseHomebrew(_ json: String) -> [AppUpdate]? {
        guard let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        func entries(_ key: String, _ source: AppUpdate.Source) -> [AppUpdate] {
            (root[key] as? [[String: Any]] ?? []).compactMap { entry in
                guard let name = entry["name"] as? String else { return nil }
                return AppUpdate(
                    name: name,
                    installedVersion: (entry["installed_versions"] as? [String])?.last ?? "?",
                    latestVersion: entry["current_version"] as? String ?? "?",
                    source: source, appStoreIdentifier: nil
                )
            }
        }
        return entries("formulae", .formula) + entries("casks", .cask)
    }

    /// Parses `mas outdated` lines such as `497799835 Xcode (15.0 -> 15.1)`.
    static func parseAppStore(_ output: String) -> [AppUpdate] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, Int(parts[0]) != nil, let open = parts[1].lastIndex(of: "(") else { return nil }
            let name = parts[1][..<open].trimmingCharacters(in: .whitespaces)
            let versions = parts[1][open...].trimmingCharacters(in: CharacterSet(charactersIn: "() ")).components(separatedBy: " -> ")
            return AppUpdate(
                name: name, installedVersion: versions.first ?? "?", latestVersion: versions.last ?? "?",
                source: .appStore, appStoreIdentifier: String(parts[0]))
        }
    }

    public static func install(_ update: AppUpdate) -> ShellResult {
        switch update.source {
        case .formula:
            guard let brew = Shell.homebrew else { return missing("Homebrew") }
            return Shell.run(brew, ["upgrade", update.name], timeout: 1800)
        case .cask:
            guard let brew = Shell.homebrew else { return missing("Homebrew") }
            return Shell.run(brew, ["upgrade", "--cask", update.name], timeout: 1800)
        case .appStore:
            guard let mas = Shell.appStoreCLI, let id = update.appStoreIdentifier else { return missing("mas") }
            return Shell.run(mas, ["upgrade", id], timeout: 1800)
        }
    }

    /// Removes a Homebrew formula or cask. `zap` also deletes a cask's app data.
    /// App Store apps are removed as app bundles; see `appBundle(for:in:)`.
    public static func uninstallHomebrew(_ update: AppUpdate, zap: Bool) -> ShellResult {
        guard let brew = Shell.homebrew else { return missing("Homebrew") }
        switch update.source {
        case .formula:
            return Shell.run(brew, ["uninstall", update.name], timeout: 600)
        case .cask:
            return Shell.run(brew, ["uninstall", "--cask"] + (zap ? ["--zap"] : []) + [update.name], timeout: 600)
        case .appStore:
            return ShellResult(status: 1, output: "", error: "\(update.name) is not a Homebrew package")
        }
    }

    /// The installed app bundle an App Store update refers to, matched by name.
    public static func appBundle(for update: AppUpdate, in apps: [InstalledApp]) -> InstalledApp? {
        let matches = apps.filter { app in
            app.name.caseInsensitiveCompare(update.name) == .orderedSame
                || ((app.path as NSString).lastPathComponent as NSString).deletingPathExtension.caseInsensitiveCompare(update.name) == .orderedSame
        }
        return matches.first(where: \.isFromAppStore) ?? matches.first
    }

    private static func missing(_ tool: String) -> ShellResult {
        ShellResult(status: 127, output: "", error: "\(tool) is not installed")
    }
}
