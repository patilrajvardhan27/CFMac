import AppKit
import CfmacCore

@MainActor
final class AnalyzeModel: ObservableObject {
    /// Breadcrumb marker for the virtual "Whole Disk" level.
    nonisolated static let wholeDisk = "/__whole_disk__"
    private static let concurrentSizers = 6

    @Published private(set) var trail: [String] = [AnalyzeModel.wholeDisk]
    @Published private(set) var entries: [DiskEntry] = []
    @Published private(set) var largestFiles: [DiskEntry] = []
    @Published private(set) var isScanning = false
    @Published private(set) var status = ""
    @Published var showsLargestFiles = false
    @Published var message: String?
    @Published var selection: String?
    @Published private(set) var volume = VolumeReading.startup()

    private struct CachedLevel {
        let entries: [DiskEntry]
        let largest: [DiskEntry]
    }

    private var cache: [String: CachedLevel] = [:]
    /// Least recently used first; bounds memory however deep the user browses.
    private var cacheOrder: [String] = []
    private static let cacheLimit = 24
    private var scanTask: Task<Void, Never>?

    var current: String { trail.last ?? Self.wholeDisk }
    var filesTotal: Int64 { entries.reduce(0) { $0 + $1.size } }

    func title(for path: String) -> String {
        if path == Self.wholeDisk { return "Whole Disk" }
        if path == Paths.home { return "Users/" + NSUserName() }
        return (path as NSString).lastPathComponent
    }

    func start() {
        if entries.isEmpty, !isScanning { load(current) }
    }

    func open(_ entry: DiskEntry) {
        guard entry.canOpen else { return }
        trail.append(entry.path)
        load(entry.path)
    }

    func jump(to index: Int) {
        guard trail.indices.contains(index), index != trail.count - 1 else { return }
        trail = Array(trail.prefix(index + 1))
        load(current)
    }

    func refresh() {
        cache[current] = nil
        load(current)
    }

    private func load(_ folder: String) {
        scanTask?.cancel()
        selection = nil
        message = nil
        volume = VolumeReading.startup()
        if let cached = cache[folder] {
            entries = cached.entries
            largestFiles = cached.largest
            return
        }
        isScanning = true
        status = folder == Self.wholeDisk ? "Measuring disk usage" : "Scanning \(title(for: folder))"
        entries = []
        largestFiles = []
        scanTask = Task {
            var level = await Task.detached(priority: .userInitiated) {
                folder == Self.wholeDisk
                    ? DiskScanner.wholeDiskRoots().map { DiskEntry(path: $0, isDirectory: true) }
                    : DiskScanner.entries(in: folder)
            }.value
            entries = level
            var largest: [[DiskEntry]] = []
            await withTaskGroup(of: DiskMeasurement.self) { group in
                var pending = level.map(\.path).makeIterator()
                func enqueue() {
                    guard let path = pending.next() else { return }
                    group.addTask(priority: .userInitiated) { DiskScanner.measure(path) }
                }
                for _ in 0..<Self.concurrentSizers { enqueue() }
                for await measurement in group {
                    guard !Task.isCancelled else { break }
                    if let index = level.firstIndex(where: { $0.path == measurement.path }) {
                        level[index].size = measurement.size
                        level[index].isSized = true
                    }
                    largest.append(measurement.largestFiles)
                    entries = level.sorted { $0.size > $1.size }
                    status = "Refining \(title(for: measurement.path))"
                    enqueue()
                }
            }
            guard !Task.isCancelled else { return }
            let sorted = level.filter { $0.size > 0 || $0.isDirectory }.sorted { $0.size > $1.size }
            entries = sorted
            largestFiles = DiskScanner.mergeLargest(largest)
            remember(CachedLevel(entries: sorted, largest: largestFiles), for: folder)
            isScanning = false
            if sorted.isEmpty {
                message = level.isEmpty ? "Folder is empty" : "No readable items found. Check Full Disk Access in System Settings."
            }
        }
    }

    private func remember(_ level: CachedLevel, for folder: String) {
        cache[folder] = level
        cacheOrder.removeAll { $0 == folder }
        cacheOrder.append(folder)
        while cacheOrder.count > Self.cacheLimit { cache[cacheOrder.removeFirst()] = nil }
    }

    func moveToTrash(_ entry: DiskEntry) {
        switch Remover.remove(entry.path, mode: .moveToTrash, protected: AppSettings.shared.protectedSet) {
        case .removed:
            entries.removeAll { $0.path == entry.path }
            largestFiles.removeAll { $0.path == entry.path || $0.path.hasPrefix(entry.path + "/") }
            // Every level above this one now reports a stale size.
            cache = cache.filter { key, _ in key != Self.wholeDisk && !entry.path.hasPrefix(key + "/") }
            cache[current] = CachedLevel(entries: entries, largest: largestFiles)
            volume = VolumeReading.startup()
        case .skipped(let reason), .failed(let reason):
            message = "Couldn't move “\(entry.name)” to Trash: \(reason)"
        }
    }
}
