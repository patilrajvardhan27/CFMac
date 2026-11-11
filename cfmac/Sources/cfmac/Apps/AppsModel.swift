import AppKit
import CfmacCore

@MainActor
final class AppsModel: ObservableObject {
    enum Segment: String, CaseIterable { case uninstall = "Uninstall", updates = "Updates", startup = "Startup" }
    enum Sort: String, CaseIterable { case name = "Name", size = "App size", lastUsed = "Last Used", installed = "Installed" }

    @Published var segment: Segment = .uninstall
    @Published var sort: Sort = .name
    @Published var ascending = true
    @Published var search = ""

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoadingApps = false
    @Published var checked: Set<String> = []
    @Published var detailApp: InstalledApp?
    @Published private(set) var remnants: [String: [Remnant]] = [:]
    @Published var remnantSelection: Set<String> = []
    @Published var keepApp = false
    @Published private(set) var uninstallLog: [String] = []
    @Published private(set) var isUninstalling = false

    @Published private(set) var updates: [AppUpdate] = []
    @Published private(set) var isCheckingUpdates = false
    @Published private(set) var updateNote: String?
    @Published private(set) var updating: Set<String> = []
    @Published private(set) var lastUpdateCheck: Date?

    @Published private(set) var startupItems: [StartupItem] = []
    @Published private(set) var isLoadingStartup = false

    private static let concurrentSizers = 4

    // MARK: Inventory

    var visibleApps: [InstalledApp] {
        let filtered =
            search.isEmpty
            ? apps
            : apps.filter {
                $0.name.localizedCaseInsensitiveContains(search) || $0.bundleIdentifier.localizedCaseInsensitiveContains(search)
            }
        return filtered.sorted { lhs, rhs in
            let ordered: Bool =
                switch sort {
                case .name: lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                case .size: lhs.size + lhs.dataSize < rhs.size + rhs.dataSize
                case .lastUsed: (lhs.lastUsed ?? .distantPast) > (rhs.lastUsed ?? .distantPast)
                case .installed: (lhs.installed ?? .distantPast) > (rhs.installed ?? .distantPast)
                }
            return ascending ? ordered : !ordered
        }
    }

    func loadApps(force: Bool = false) {
        guard force || apps.isEmpty, !isLoadingApps else { return }
        isLoadingApps = true
        let protected = AppSettings.shared.protectedSet
        Task {
            let found = await Task.detached(priority: .userInitiated) { AppInventory.discover() }.value
            apps = found
            isLoadingApps = false
            // Size bundles and their data a few at a time, updating rows as results arrive.
            await withTaskGroup(of: (String, Int64, [Remnant]).self) { group in
                var pending = found.makeIterator()
                func enqueue() {
                    guard let app = pending.next() else { return }
                    group.addTask(priority: .utility) {
                        (app.path, DiskUsage.size(of: app.path), AppInventory.remnants(of: app, protected: protected))
                    }
                }
                for _ in 0..<Self.concurrentSizers { enqueue() }
                for await (path, size, leftovers) in group {
                    if let index = apps.firstIndex(where: { $0.path == path }) {
                        apps[index].size = size
                        apps[index].dataSize = leftovers.reduce(0) { $0 + $1.size }
                    }
                    remnants[path] = leftovers
                    enqueue()
                }
            }
        }
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    // MARK: Uninstall

    func openDetail(_ app: InstalledApp) {
        let leftovers = remnants[app.path] ?? []
        remnantSelection = AppSettings.shared.removeAppData ? Set(leftovers.filter { $0.confidence == .automatic }.map(\.path)) : []
        keepApp = false
        detailApp = app
    }

    func toggleChecked(_ app: InstalledApp) {
        if checked.remove(app.path) == nil { checked.insert(app.path) }
    }

    var checkedRemovalSize: Int64 {
        let removeData = AppSettings.shared.removeAppData
        return apps.filter { checked.contains($0.path) }.reduce(Int64(0)) { total, app in
            let data = (remnants[app.path] ?? []).filter { $0.confidence == .automatic }.reduce(Int64(0)) { $0 + $1.size }
            return total + app.size + (removeData ? data : 0)
        }
    }

    /// Uninstalls the checked apps with their automatically matched data.
    func uninstallChecked() {
        let removeData = AppSettings.shared.removeAppData
        let targets = apps.filter { checked.contains($0.path) }.map { app in
            (app, false, removeData ? (remnants[app.path] ?? []).filter { $0.confidence == .automatic } : [])
        }
        uninstall(targets)
    }

    /// Uninstalls the detail app (or clears only its data) with the selected leftovers.
    func uninstallDetail() {
        guard let app = detailApp else { return }
        let chosen = (remnants[app.path] ?? []).filter { remnantSelection.contains($0.path) }
        uninstall([(app, keepApp, chosen)])
    }

    private func uninstall(_ targets: [(app: InstalledApp, keepApp: Bool, remnants: [Remnant])]) {
        guard !isUninstalling, !targets.isEmpty else { return }
        isUninstalling = true
        uninstallLog = []
        let protected = AppSettings.shared.protectedSet
        Task {
            for target in targets {
                if !target.keepApp, !(await quit(target.app)) {
                    uninstallLog.append("\(target.app.name) is running, skipped")
                    continue
                }
                let log = await Task.detached(priority: .userInitiated) {
                    AppInventory.uninstall(target.app, keepApp: target.keepApp, remnants: target.remnants, protected: protected)
                }.value
                uninstallLog += log
                let removed = Set(target.remnants.map(\.path))
                remnants[target.app.path] = (remnants[target.app.path] ?? []).filter { !removed.contains($0.path) }
                if !target.keepApp { apps.removeAll { $0.path == target.app.path } }
                checked.remove(target.app.path)
            }
            detailApp = nil
            isUninstalling = false
            UsageStats.shared.recordUninstall(count: targets.filter { !$0.keepApp }.count)
            SoundPlayer.shared.playCompletion(for: .uninstall)
        }
    }

    /// Asks a running app to quit and waits up to five seconds.
    private func quit(_ app: InstalledApp) async -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
        guard !running.isEmpty else { return true }
        uninstallLog.append("Quit \(app.name)")
        running.forEach { $0.terminate() }
        for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return running.allSatisfy(\.isTerminated)
    }

    func dismissLog() { uninstallLog = [] }

    // MARK: Updates

    var visibleUpdates: [AppUpdate] {
        let ignored = AppSettings.shared.ignoredUpdates
        return updates.filter { !ignored.contains($0.id) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }

    func checkUpdates() {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        updateNote = nil
        Task {
            let check = await Task.detached(priority: .userInitiated) { Updates.check() }.value
            updates = check.updates
            updateNote = check.note
            lastUpdateCheck = Date()
            isCheckingUpdates = false
        }
    }

    func install(_ update: AppUpdate) {
        guard !updating.contains(update.id) else { return }
        updating.insert(update.id)
        Task {
            let result = await Task.detached(priority: .userInitiated) { Updates.install(update) }.value
            updating.remove(update.id)
            if result.succeeded {
                updates.removeAll { $0.id == update.id }
                // One sound when the last running update finishes, not one per app.
                if updating.isEmpty { SoundPlayer.shared.playCompletion(for: .update) }
            } else {
                updateNote = "\(update.name): \(result.error.split(separator: "\n").last.map(String.init) ?? "update failed")"
            }
        }
    }

    func installAll() { visibleUpdates.forEach(install) }

    /// Uninstalls an item from the Updates list. Homebrew items go through `brew uninstall`
    /// (`zap` also removes a cask's app data); App Store apps are quit and moved to the Trash
    /// with their automatically matched data.
    func uninstallUpdate(_ update: AppUpdate, zap: Bool) {
        guard !updating.contains(update.id) else { return }
        updating.insert(update.id)
        Task {
            let failure: String?
            if update.source == .appStore {
                failure = await uninstallAppStoreApp(update)
            } else {
                let result = await Task.detached(priority: .userInitiated) { Updates.uninstallHomebrew(update, zap: zap) }.value
                failure = result.succeeded ? nil : (result.error.split(separator: "\n").last.map(String.init) ?? "uninstall failed")
            }
            updating.remove(update.id)
            if let failure {
                updateNote = "\(update.name): \(failure)"
            } else {
                updates.removeAll { $0.id == update.id }
                UsageStats.shared.recordUninstall(count: 1)
                SoundPlayer.shared.playCompletion(for: .uninstall)
                // Casks and App Store apps live in /Applications, so refresh that list.
                if update.source != .formula, !apps.isEmpty { loadApps(force: true) }
            }
        }
    }

    /// Returns an error message, or nil when the app was moved to the Trash.
    private func uninstallAppStoreApp(_ update: AppUpdate) async -> String? {
        let known = apps.isEmpty ? await Task.detached(priority: .userInitiated) { AppInventory.discover() }.value : apps
        guard let app = Updates.appBundle(for: update, in: known) else { return "app not found in Applications" }
        guard await quit(app) else { return "\(app.name) is still running" }
        let protected = AppSettings.shared.protectedSet
        let removeData = AppSettings.shared.removeAppData
        let log = await Task.detached(priority: .userInitiated) { () -> [String] in
            let leftovers = removeData ? AppInventory.remnants(of: app, protected: protected).filter { $0.confidence == .automatic } : []
            return AppInventory.uninstall(app, keepApp: false, remnants: leftovers, protected: protected)
        }.value
        let removed = log.first == "Moved \(app.name) to Trash"
        return removed ? nil : (log.first ?? "uninstall failed")
    }

    func ignore(_ update: AppUpdate) {
        AppSettings.shared.ignoreUpdate(update.id)
        objectWillChange.send()
    }

    // MARK: Startup

    func loadStartup() {
        isLoadingStartup = true
        Task {
            startupItems = await Task.detached(priority: .userInitiated) { StartupItems.discover() }.value
            isLoadingStartup = false
        }
    }

    func setEnabled(_ item: StartupItem, _ enabled: Bool) {
        Task {
            await Task.detached { StartupItems.setEnabled(item, enabled) }.value
            loadStartup()
        }
    }

    func moveToTrash(_ item: StartupItem) {
        let protected = AppSettings.shared.protectedSet
        Task {
            _ = await Task.detached { StartupItems.moveToTrash(item, protected: protected) }.value
            loadStartup()
        }
    }
}
