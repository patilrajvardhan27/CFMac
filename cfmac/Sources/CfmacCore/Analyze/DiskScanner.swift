import Foundation

public struct DiskEntry: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public var size: Int64
    public var isSized: Bool
    /// A personal-data store (Photos, Mail, ...): listed by name only, never sized or opened.
    public let isPrivate: Bool
    public let modified: Date?

    public init(path: String, isDirectory: Bool, size: Int64 = 0, isSized: Bool = false, modified: Date? = nil) {
        self.path = path
        self.name = (path as NSString).lastPathComponent
        self.isDirectory = isDirectory
        self.size = size
        self.isSized = isSized
        self.modified = modified
        self.isPrivate = PrivacyGuard.isPrivate(path)
    }

    public var isBundle: Bool { isDirectory && name.hasSuffix(".app") }
    /// Folders the user can step into.
    public var canOpen: Bool { isDirectory && !isBundle && !isPrivate }

    public var kind: Kind { Kind(entry: self) }

    public enum Kind: String, Sendable {
        case folder = "Folder", hiddenFolder = "Hidden Folder", app = "App", video = "Videos", image = "Images"
        case audio = "Audio", archive = "Archive", diskImage = "Disk image", installer = "App / installer"
        case document = "Documents", design = "Design", developer = "Dev files", other = "Other"

        init(entry: DiskEntry) {
            if entry.isDirectory {
                self = entry.isBundle ? .app : entry.name.hasPrefix(".") ? .hiddenFolder : .folder
                return
            }
            switch (entry.name as NSString).pathExtension.lowercased() {
            case "mov", "mp4", "m4v", "mkv", "avi": self = .video
            case "jpg", "jpeg", "png", "heic", "gif", "tiff", "raw", "psd": self = .image
            case "mp3", "m4a", "wav", "aiff", "flac": self = .audio
            case "zip", "gz", "tar", "rar", "7z", "xz", "tgz": self = .archive
            case "dmg", "iso", "img", "sparseimage": self = .diskImage
            case "pkg", "mpkg": self = .installer
            case "pdf", "doc", "docx", "pages", "key", "numbers", "txt", "md": self = .document
            case "sketch", "fig", "ai", "xd": self = .design
            case "swift", "js", "ts", "py", "go", "rs", "c", "h", "json", "o", "a": self = .developer
            default: self = .other
            }
        }

        public var symbol: String {
            switch self {
            case .folder, .hiddenFolder: "folder"
            case .app: "app"
            case .video: "film"
            case .image: "photo"
            case .audio: "music.note"
            case .archive: "archivebox"
            case .diskImage: "opticaldiscdrive"
            case .installer: "shippingbox"
            case .document: "doc.text"
            case .design: "paintbrush"
            case .developer: "chevron.left.forwardslash.chevron.right"
            case .other: "doc"
            }
        }
    }
}

/// Size and largest-file facts for one entry, from a single walk.
public struct DiskMeasurement: Sendable {
    public let path: String
    public let size: Int64
    public let largestFiles: [DiskEntry]
}

public enum DiskScanner {
    static let largestFileCount = 20

    /// User-reachable areas of the startup disk; macOS system volumes are skipped.
    public static func wholeDiskRoots(home: String = Paths.home) -> [String] {
        [home, "/Applications", "/Library", "/opt", "/usr/local", "/Users/Shared"].filter(DiskUsage.exists)
    }

    public static func entries(in folder: String) -> [DiskEntry] {
        DiskUsage.children(of: folder).map { path in
            DiskEntry(path: path, isDirectory: DiskUsage.isDirectory(path), modified: DiskUsage.modificationDate(path))
        }
    }

    public static func measure(_ path: String) -> DiskMeasurement {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard !PrivacyGuard.isPrivate(path) else { return DiskMeasurement(path: path, size: 0, largestFiles: []) }
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else {
            return DiskMeasurement(path: path, size: 0, largestFiles: [])
        }
        if values.isDirectory != true {
            let size = Int64(values.totalFileAllocatedSize ?? 0)
            let entry = DiskEntry(path: path, isDirectory: false, size: size, isSized: true, modified: values.contentModificationDate)
            return DiskMeasurement(path: path, size: size, largestFiles: [entry])
        }
        var total: Int64 = 0
        var largest = TopFiles(limit: largestFileCount)
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), errorHandler: { _, _ in true })
        var visited = 0
        while let child = walker?.nextObject() as? URL {
            visited += 1
            if visited % 5000 == 0, Task.isCancelled { break }
            guard let childValues = try? child.resourceValues(forKeys: keys) else { continue }
            if childValues.isDirectory == true {
                if PrivacyGuard.isPrivate(child.path) { walker?.skipDescendants() }
                continue
            }
            let size = Int64(childValues.totalFileAllocatedSize ?? 0)
            total += size
            largest.offer(size) {
                DiskEntry(path: child.path, isDirectory: false, size: size, isSized: true, modified: childValues.contentModificationDate)
            }
        }
        return DiskMeasurement(path: path, size: total, largestFiles: largest.sorted)
    }

    /// Merges per-entry largest files into one list.
    public static func mergeLargest(_ lists: [[DiskEntry]], limit: Int = 50) -> [DiskEntry] {
        Array(lists.joined().sorted { $0.size > $1.size }.prefix(limit))
    }
}

/// Keeps the `limit` largest files seen, creating entries only for candidates.
struct TopFiles {
    let limit: Int
    private(set) var entries: [DiskEntry] = []
    private var threshold: Int64 = 0

    init(limit: Int) { self.limit = limit }

    mutating func offer(_ size: Int64, _ make: () -> DiskEntry) {
        guard entries.count < limit || size > threshold else { return }
        entries.append(make())
        if entries.count > limit * 2 {
            entries.sort { $0.size > $1.size }
            entries.removeLast(entries.count - limit)
            threshold = entries.last?.size ?? 0
        }
    }

    var sorted: [DiskEntry] { Array(entries.sorted { $0.size > $1.size }.prefix(limit)) }
}
