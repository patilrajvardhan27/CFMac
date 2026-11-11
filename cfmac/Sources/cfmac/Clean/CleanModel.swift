import AppKit
import CfmacCore

@MainActor
final class CleanModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, found, review, cleaning, done }

    struct SectionGroup {
        let section: CleanSection
        let items: [CleanItem]
        let total: Int64
    }

    @Published var phase: Phase = .idle
    @Published private(set) var status = ""
    @Published private(set) var progress: Double = 0
    @Published private(set) var items: [CleanItem] = [] { didSet { regroup() } }
    @Published var selection: Set<String> = []
    @Published var focusedSection: CleanSection?
    @Published private(set) var outcomes: [CleanOutcome] = []
    @Published private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess
    /// Items the last clean moved to the Trash, for Put Back.
    @Published private(set) var lastRestorable: [RestorableItem] = []
    @Published private(set) var putBackMessage: String?

    /// Built once per change of `items` (O(items)), not on every redraw.
    @Published private(set) var groups: [SectionGroup] = []
    private var totalsBySection: [CleanSection: Int64] = [:]
    private var scanTask: Task<Void, Never>?

    private(set) var foundTotal: Int64 = 0
    private(set) var cleanableTotal: Int64 = 0
    var selectedTotal: Int64 { items.lazy.filter { self.selection.contains($0.path) }.reduce(0) { $0 + $1.size } }
    var freedTotal: Int64 { outcomes.reduce(0) { $0 + $1.freed } }

    func total(of section: CleanSection) -> Int64 { totalsBySection[section] ?? 0 }

    private func regroup() {
        let grouped = Dictionary(grouping: items, by: \.section)
        groups = CleanSection.allCases.compactMap { section in
            guard let list = grouped[section] else { return nil }
            return SectionGroup(section: section, items: list, total: list.reduce(0) { $0 + $1.size })
        }
        totalsBySection = Dictionary(uniqueKeysWithValues: groups.map { ($0.section, $0.total) })
        foundTotal = groups.reduce(0) { $0 + $1.total }
        cleanableTotal = foundTotal - (totalsBySection[.storage] ?? 0)
    }

    // MARK: Scanning

    func scan() {
        scanTask?.cancel()
        hasFullDiskAccess = Permissions.hasFullDiskAccess
        phase = .scanning
        progress = 0
        status = "Looking for caches"
        let fullDiskAccess = hasFullDiskAccess
        let settings = AppSettings.shared
        let protected = settings.protectedSet
        let folders = settings.customFolders
        scanTask = Task {
            let found = await CleanEngine.scan(fullDiskAccess: fullDiskAccess, protected: protected, customFolders: folders) { fraction, label in
                await self.report(fraction: fraction, label: label)
            }
            guard !Task.isCancelled else { return }
            items = found
            apply(settings.cleanPreset)
            phase = .found
        }
    }

    private func report(fraction: Double, label: String) {
        progress = fraction
        if !label.isEmpty { status = "Scanning \(label)" }
    }

    func cancelScan() {
        scanTask?.cancel()
        phase = items.isEmpty ? .idle : .found
    }

    // MARK: Selection

    func apply(_ preset: CleanPreset) {
        selection = preset.selection(from: items)
    }

    /// The preset matching the current selection, or nil for a custom selection.
    var matchingPreset: CleanPreset? {
        CleanPreset.allCases.first { $0.selection(from: items) == selection }
    }

    func toggle(_ item: CleanItem) {
        guard item.safety != .lookUp else { return }
        if selection.remove(item.path) == nil { selection.insert(item.path) }
    }

    func neverClean(_ item: CleanItem) {
        AppSettings.shared.protect(item.path)
        selection.remove(item.path)
        items.removeAll { $0.path == item.path }
    }

    func runningOwner(of item: CleanItem) -> NSRunningApplication? {
        SystemActions.runningOwner(of: item.owners)
    }

    // MARK: Cleaning

    func clean() {
        let chosen = items.filter { selection.contains($0.path) && $0.safety != .lookUp }
        guard !chosen.isEmpty else { return }
        phase = .cleaning
        progress = 0
        status = "Preparing clean"
        putBackMessage = nil
        let mode = AppSettings.shared.removalMode
        let protected = AppSettings.shared.protectedSet
        let owners = Dictionary(uniqueKeysWithValues: chosen.map { ($0.path, runningOwner(of: $0)?.localizedName) })
        Task {
            var results: [CleanOutcome] = []
            results.reserveCapacity(chosen.count)
            for (index, item) in chosen.enumerated() {
                status = "Cleaning \(item.label)"
                let owner = owners[item.path] ?? nil
                let outcome = await Task.detached(priority: .userInitiated) {
                    CleanEngine.clean(item, mode: mode, runningOwner: owner, protected: protected)
                }.value
                results.append(outcome)
                progress = Double(index + 1) / Double(chosen.count)
            }
            outcomes = results
            lastRestorable = results.flatMap(\.restorable)
            let cleaned = Set(results.filter { $0.kind == .cleaned || $0.kind == .movedToTrash }.map(\.item.path))
            items.removeAll { cleaned.contains($0.path) && !$0.contentsOnly }
            selection.subtract(cleaned)
            UsageStats.shared.recordClean(freedTotal)
            phase = .done
            SoundPlayer.shared.playCompletion(for: .clean)
        }
    }

    /// Moves everything the last clean put in the Trash back where it was.
    func putBack() {
        let items = lastRestorable
        guard !items.isEmpty else { return }
        Task {
            let failed = await Task.detached(priority: .userInitiated) { Remover.putBack(items) }.value
            lastRestorable = failed
            putBackMessage =
                failed.isEmpty
                ? "Put back \(items.count) items"
                : "Put back \(items.count - failed.count) of \(items.count). The rest were changed or replaced since."
        }
    }

    func finish() {
        phase = items.isEmpty ? .idle : .found
    }
}
