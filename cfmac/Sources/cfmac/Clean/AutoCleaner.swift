import AppKit
import CfmacCore

/// Cleans Safe items on a schedule or when the disk gets low. Automatic cleans always move
/// items to the Trash and can be put back for a day.
@MainActor
final class AutoCleaner: ObservableObject {
    static let shared = AutoCleaner()

    /// How long the last automatic clean can be undone from cfmac.
    static let undoWindow: TimeInterval = 24 * 3600
    /// Checking is cheap; cleaning only happens when a trigger is due.
    private static let checkInterval: TimeInterval = 30 * 60

    struct Run: Codable {
        let date: Date
        let freed: Int64
        var restorable: [RestorableItem]
    }

    @Published private(set) var lastRun: Run?
    @Published private(set) var isRunning = false
    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private static let storeKey = "autoClean.lastRun"
    private static let baselineKey = "autoClean.enabledAt"

    private init() {
        if let data = defaults.data(forKey: Self.storeKey) { lastRun = try? JSONDecoder().decode(Run.self, from: data) }
    }

    var canUndo: Bool {
        guard let lastRun, !lastRun.restorable.isEmpty else { return false }
        return Date().timeIntervalSince(lastRun.date) < Self.undoWindow
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runIfDue() }
        }
        timer?.tolerance = 60
        runIfDue()
    }

    func runIfDue() {
        let policy = AppSettings.shared.autoClean
        guard policy.isEnabled, !isRunning else {
            if !policy.isEnabled { defaults.removeObject(forKey: Self.baselineKey) }
            return
        }
        // The first scheduled run comes one interval after automatic cleaning is turned on.
        let baseline =
            lastRun?.date ?? (defaults.object(forKey: Self.baselineKey) as? Date)
            ?? {
                let now = Date()
                defaults.set(now, forKey: Self.baselineKey)
                return now
            }()
        guard let trigger = policy.trigger(now: Date(), lastRun: baseline, freeBytes: VolumeReading.startup().available) else { return }
        run(reason: trigger == .lowDisk ? "your disk was nearly full" : "it was scheduled")
    }

    /// Scans and moves every Safe item to the Trash, skipping anything an app is using.
    func run(reason: String) {
        guard !isRunning else { return }
        isRunning = true
        let settings = AppSettings.shared
        let protected = settings.protectedSet
        Task {
            let items = await CleanEngine.scan(fullDiskAccess: Permissions.hasFullDiskAccess, protected: protected) { _, _ in }
            let safe = items.filter { $0.safety == .safe && !$0.permanentOnly }
            let owners = Dictionary(uniqueKeysWithValues: safe.map { ($0.path, SystemActions.runningOwner(of: $0.owners)?.localizedName) })
            let outcomes = await Task.detached(priority: .utility) {
                safe.map { CleanEngine.clean($0, mode: .moveToTrash, runningOwner: owners[$0.path] ?? nil, protected: protected) }
            }.value
            let freed = outcomes.reduce(0) { $0 + $1.freed }
            let run = Run(date: Date(), freed: freed, restorable: outcomes.flatMap(\.restorable))
            save(run)
            isRunning = false
            UsageStats.shared.recordClean(freed)
            if freed > 0 {
                Notifier.post(
                    title: "cfmac cleaned \(Format.bytes(freed))",
                    body: "Safe items were moved to the Trash because \(reason). You can put them back from Clean for 24 hours.")
                SoundPlayer.shared.playCompletion(for: .clean)
            }
        }
    }

    func undo() {
        guard let run = lastRun, canUndo else { return }
        Task {
            let failed = await Task.detached(priority: .userInitiated) { Remover.putBack(run.restorable) }.value
            var updated = run
            updated.restorable = failed
            save(updated)
        }
    }

    private func save(_ run: Run) {
        lastRun = run
        if let data = try? JSONEncoder().encode(run) { defaults.set(data, forKey: Self.storeKey) }
    }
}
