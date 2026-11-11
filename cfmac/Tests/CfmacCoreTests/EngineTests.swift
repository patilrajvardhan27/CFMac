import CoreGraphics
import Foundation
import Testing

@testable import CfmacCore

@Suite("Clean")
struct CleanTests {
    @Test(arguments: [
        ("Google Chrome", CleanSection.browsers), ("Brave-Browser", .browsers), ("Microsoft Edge", .browsers),
        ("Slack", .communication), ("discord", .communication), ("Claude", .ai), ("Cursor", .ai),
        ("Code", .developer), ("Figma", .design), ("Dropbox", .cloud), ("Research Tool", .app), ("Searchlight", .app),
    ])
    func classifiesOwnersByWholeWord(owner: String, section: CleanSection) {
        #expect(CleanCatalog.section(forOwner: owner) == section)
    }

    @Test func everyDiscoveredCandidatePassesTheGuard() {
        let candidates = CleanCatalog.discover(fullDiskAccess: Permissions.hasFullDiskAccess)
        for candidate in candidates where candidate.section != .storage {
            // contentsOnly folders are emptied, so their children are what get removed.
            let removedPath = candidate.contentsOnly ? candidate.path + "/child" : candidate.path
            #expect(SafetyGuard.check(removedPath, protected: []) == nil, "\(candidate.path)")
        }
        let paths = candidates.map(\.path)
        #expect(Set(paths).count == paths.count, "duplicates")
        for path in paths {
            #expect(!paths.contains { $0 != path && path.hasPrefix($0 + "/") }, "nested: \(path)")
        }
    }

    @Test func cleansFolderContentsButKeepsTheFolder() throws {
        let folder = try TemporaryFolder()
        try folder.file("one.log", bytes: 100_000)
        try folder.file("two/three.log", bytes: 100_000)
        let candidate = CleanCandidate(path: folder.path, label: "Logs", detail: "", section: .system, safety: .safe, contentsOnly: true)
        let outcome = CleanEngine.clean(CleanItem(candidate: candidate, size: 200_000), mode: .deletePermanently, runningOwner: nil, protected: [])
        #expect(outcome.kind == .cleaned)
        #expect(outcome.freed >= 200_000)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(DiskUsage.children(of: folder.path).isEmpty)
    }

    @Test func skipsItemsInUse() throws {
        let folder = try TemporaryFolder()
        let file = try folder.file("cache.bin", bytes: 10)
        let candidate = CleanCandidate(path: file, label: "Cache", detail: "", section: .app, safety: .safe)
        let outcome = CleanEngine.clean(CleanItem(candidate: candidate, size: 10), mode: .deletePermanently, runningOwner: "Example", protected: [])
        #expect(outcome.kind == .skipped)
        #expect(outcome.reason == "Example is running")
        #expect(FileManager.default.fileExists(atPath: file))
    }

    @Test func recognizesBundleIdentifiers() {
        #expect(AppLookup.looksLikeBundleIdentifier("com.example.app"))
        #expect(!AppLookup.looksLikeBundleIdentifier("com.apple.finder"))
        #expect(!AppLookup.looksLikeBundleIdentifier("Example App"))
        #expect(!AppLookup.looksLikeBundleIdentifier("com..app"))
    }
}

@Suite("Treemap")
struct TreemapTests {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    @Test func fillsTheBoundsProportionally() {
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rects = Treemap.layout(values, in: bounds)
        let total = values.reduce(0, +)
        for (rect, value) in zip(rects, values) {
            #expect(abs(Double(rect.width * rect.height) - value / total * 240_000) < 1)
            #expect(bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect))
        }
        #expect(abs(rects.reduce(0) { $0 + $1.width * $1.height } - 240_000) < 1)
    }

    @Test func tilesDoNotOverlap() {
        let rects = Treemap.layout([9, 7, 5, 3, 2, 1, 1, 0.5], in: bounds)
        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] {
                #expect(a.intersection(b).width * a.intersection(b).height < 0.5)
            }
        }
    }

    @Test func handlesEmptyInput() {
        #expect(Treemap.layout([], in: bounds).isEmpty)
        #expect(Treemap.layout([0, 0], in: bounds) == [.zero, .zero])
        #expect(Treemap.layout([1], in: .zero) == [.zero])
    }
}

@Suite("Disk scanner")
struct DiskScannerTests {
    @Test func measuresSizeAndLargestFiles() throws {
        let folder = try TemporaryFolder()
        try folder.file("small.bin", bytes: 50_000)
        try folder.file("deep/large.bin", bytes: 900_000)
        try folder.file("medium.bin", bytes: 400_000)
        let measurement = DiskScanner.measure(folder.path)
        #expect(measurement.size >= 1_350_000)
        #expect(measurement.largestFiles.map(\.name).prefix(2) == ["large.bin", "medium.bin"])
    }

    @Test func keepsOnlyTheLargestFiles() {
        var top = TopFiles(limit: 3)
        for size in [5, 1, 9, 3, 7, 2, 8] as [Int64] {
            top.offer(size) { DiskEntry(path: "/f\(size)", isDirectory: false, size: size, isSized: true) }
        }
        #expect(top.sorted.map(\.size) == [9, 8, 7])
    }

    @Test func classifiesKinds() {
        #expect(DiskEntry(path: "/a/movie.MOV", isDirectory: false).kind == .video)
        #expect(DiskEntry(path: "/a/Thing.app", isDirectory: true).kind == .app)
        #expect(DiskEntry(path: "/a/.git", isDirectory: true).kind == .hiddenFolder)
        #expect(!DiskEntry(path: "/a/Thing.app", isDirectory: true).canOpen)
    }
}
