import Foundation

public struct CleanItem: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let label: String
    public let detail: String
    public let section: CleanSection
    public let safety: Safety
    public let size: Int64
    public let owners: [String]
    public let contentsOnly: Bool
    public let permanentOnly: Bool
    /// Web search that explains how to free this space.
    public let lookUpQuery: String

    public init(candidate: CleanCandidate, size: Int64) {
        path = candidate.path
        label = candidate.label
        detail = candidate.detail
        section = candidate.section
        safety = candidate.safety
        owners = candidate.owners
        contentsOnly = candidate.contentsOnly
        permanentOnly = candidate.permanentOnly
        lookUpQuery = candidate.lookUp ?? WebLookup.freeSpaceQuery(for: candidate.label)
        self.size = size
    }
}

public struct CleanOutcome: Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case cleaned = "Cleaned"
        case movedToTrash = "Moved to Trash"
        case skipped = "Skipped"
        case failed = "Failed"
    }

    public let id = UUID()
    public let item: CleanItem
    public let kind: Kind
    public let reason: String?
    public let freed: Int64
    /// Items moved to the Trash by this clean, for putting back.
    public var restorable: [RestorableItem] = []
}

public enum CleanEngine {
    /// Items smaller than this are not worth listing.
    static let minimumSize: Int64 = 64 * 1024
    static let concurrentSizers = 8

    /// Sizes every candidate with bounded concurrency. `progress` receives (fraction, label).
    public static func scan(
        fullDiskAccess: Bool,
        protected: Set<String>,
        customFolders: [CustomCleanFolder] = [],
        progress: @escaping @Sendable (Double, String) async -> Void
    ) async -> [CleanItem] {
        let candidates = CleanCatalog.discover(fullDiskAccess: fullDiskAccess, customFolders: customFolders).filter { !protected.contains($0.path) }
        let total = max(1, candidates.count)
        var items: [CleanItem] = []
        await withTaskGroup(of: CleanItem?.self) { group in
            var pending = candidates.makeIterator()
            func enqueue() {
                guard let candidate = pending.next() else { return }
                group.addTask {
                    let size = DiskUsage.size(of: candidate.path) { Task.isCancelled }
                    return size >= minimumSize ? CleanItem(candidate: candidate, size: size) : nil
                }
            }
            for _ in 0..<concurrentSizers { enqueue() }
            var finished = 0
            for await item in group {
                finished += 1
                if let item { items.append(item) }
                await progress(Double(finished) / Double(total), item?.label ?? "")
                enqueue()
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Removes one item. `runningOwner` names an app currently using it, which skips the item.
    public static func clean(_ item: CleanItem, mode: RemovalMode, runningOwner: String?, protected: Set<String>) -> CleanOutcome {
        if let runningOwner {
            return CleanOutcome(item: item, kind: .skipped, reason: "\(runningOwner) is running", freed: 0)
        }
        let effectiveMode: RemovalMode = item.permanentOnly ? .deletePermanently : mode
        let targets = item.contentsOnly ? DiskUsage.children(of: item.path) : [item.path]
        var freed: Int64 = 0
        var restorable: [RestorableItem] = []
        var skipped: [String] = []
        var failures: [String] = []
        for target in targets {
            let size = DiskUsage.size(of: target)
            switch Remover.remove(target, mode: effectiveMode, protected: protected) {
            case .removed(_, let trashedAt):
                freed += size
                if let trashedAt { restorable.append(RestorableItem(originalPath: target, trashedPath: trashedAt, size: size)) }
            case .skipped(let reason): skipped.append(reason)
            case .failed(let reason): failures.append(reason)
            }
        }
        if freed == 0 {
            if let failure = failures.first { return CleanOutcome(item: item, kind: .failed, reason: failure, freed: 0) }
            if let skip = skipped.first { return CleanOutcome(item: item, kind: .skipped, reason: skip, freed: 0) }
        }
        let kind: CleanOutcome.Kind = effectiveMode == .moveToTrash ? .movedToTrash : .cleaned
        let note = failures.isEmpty ? nil : "\(failures.count) of \(targets.count) items could not be removed"
        return CleanOutcome(item: item, kind: kind, reason: note, freed: freed, restorable: restorable)
    }
}
