import Foundation
import Testing

@testable import CfmacCore

@Suite("Privacy guard")
struct PrivacyGuardTests {
    let home = Paths.home

    @Test(arguments: [
        "Library/Mail/V10", "Library/Messages/chat.db", "Library/Safari/History.db", "Library/Calendars",
        "Library/Application Support/AddressBook/Sources", "Library/Keychains/login.keychain-db", "Library/Cookies",
        "Library/Containers/com.apple.Notes/Data", "Library/Group Containers/group.com.apple.notes",
        "Pictures/Photos Library.photoslibrary", "Pictures/Photos Library.photoslibrary/originals/a.heic",
    ])
    func personalStoresArePrivate(relative: String) {
        #expect(PrivacyGuard.isPrivate(home + "/" + relative), "\(relative)")
    }

    @Test(arguments: ["Library/Caches/com.example.app", "Documents/report.pdf", "Downloads", "Library/Containers/com.example.app", "Library/Mailboxes"])
    func ordinaryFilesAreNot(relative: String) {
        #expect(!PrivacyGuard.isPrivate(home + "/" + relative), "\(relative)")
    }

    @Test func photoLibrariesArePrivateAnywhere() {
        #expect(PrivacyGuard.isPrivate("/Volumes/Backup/Family.photoslibrary/database"))
        #expect(!PrivacyGuard.isPrivate("/Volumes/Backup/photoslibrary-notes.txt"))
    }

    @Test func sizingAndListingSkipPrivateStores() throws {
        let folder = try TemporaryFolder()
        try folder.file("Trip.photoslibrary/originals/photo.heic", bytes: 900_000)
        try folder.file("visible.bin", bytes: 100_000)
        let size = DiskUsage.size(of: folder.path)
        #expect(size >= 100_000 && size < 900_000)
        #expect(DiskUsage.children(of: folder.path + "/Trip.photoslibrary").isEmpty)
        #expect(DiskScanner.measure(folder.path + "/Trip.photoslibrary").size == 0)
        #expect(DiskEntry(path: folder.path + "/Trip.photoslibrary", isDirectory: true).isPrivate)
        #expect(!DiskEntry(path: folder.path + "/Trip.photoslibrary", isDirectory: true).canOpen)
    }

    @Test func privateStoresCannotBeRemoved() {
        #expect(SafetyGuard.check(home + "/Library/Mail/V10/x", protected: []) == .protectedData)
        #expect(SafetyGuard.check(home + "/Pictures/A.photoslibrary", protected: []) == .protectedData)
    }

    /// cfmac's sources must not contain networking or personal-data APIs, or web links.
    @Test func sourcesUseNoNetworkingOrPersonalDataAPIs() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let forbidden = [
            "URLSession", "URLRequest", "NSURLConnection", "NWConnection", "WKWebView", "http://", "https://",
            "PHPhotoLibrary", "CNContactStore", "EKEventStore", "CLLocationManager", "AVCaptureDevice",
            "AVAudioRecorder", "INFocusStatusCenter", "desktopImageURL",
        ]
        let enumerator = try #require(FileManager.default.enumerator(atPath: sources.path))
        var checked = 0
        for case let relative as String in enumerator where relative.hasSuffix(".swift") {
            // The plist DOCTYPE names a DTD by URL; nothing ever fetches it.
            let text = try String(contentsOf: sources.appendingPathComponent(relative), encoding: .utf8)
                .replacingOccurrences(of: "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"", with: "")
            checked += 1
            for term in forbidden {
                #expect(!text.contains(term), "\(relative) uses \(term)")
            }
        }
        #expect(checked > 30)
    }
}

@Suite("Schedules")
struct ScheduleTests {
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    @Test func quietHoursCrossMidnight() {
        let night = QuietHours(isEnabled: true, start: 22 * 60, end: 7 * 60)
        #expect(night.contains(date(23)))
        #expect(night.contains(date(3)))
        #expect(!night.contains(date(7)))
        #expect(!night.contains(date(12)))
        let lunch = QuietHours(isEnabled: true, start: 12 * 60, end: 13 * 60)
        #expect(lunch.contains(date(12, 30)))
        #expect(!lunch.contains(date(13)))
        #expect(!QuietHours(isEnabled: false).contains(date(23)))
        #expect(QuietHours.label(minutes: 7 * 60 + 5) == "07:05")
    }

    @Test func autoCleanTriggers() {
        let now = Date()
        let weekly = AutoCleanPolicy(frequency: .weekly)
        #expect(weekly.trigger(now: now, lastRun: now.addingTimeInterval(-8 * 86_400), freeBytes: 100_000_000_000) == .schedule)
        #expect(weekly.trigger(now: now, lastRun: now.addingTimeInterval(-86_400), freeBytes: 100_000_000_000) == nil)
        let lowDisk = AutoCleanPolicy(frequency: .off, lowDiskGigabytes: 20)
        #expect(lowDisk.trigger(now: now, lastRun: nil, freeBytes: 10_000_000_000) == .lowDisk)
        #expect(lowDisk.trigger(now: now, lastRun: now.addingTimeInterval(-60), freeBytes: 10_000_000_000) == nil)
        #expect(lowDisk.trigger(now: now, lastRun: nil, freeBytes: 50_000_000_000) == nil)
        #expect(!AutoCleanPolicy().isEnabled)
    }

    @Test func milestones() {
        #expect(Milestones.reached(500_000_000) == nil)
        #expect(Milestones.reached(12_000_000_000) == 10_000_000_000)
        let next = Milestones.next(after: 7_500_000_000)
        #expect(next?.target == 10_000_000_000)
        #expect(abs((next?.progress ?? 0) - 0.5) < 0.0001)
        #expect(Milestones.next(after: 2_000_000_000_000) == nil)
    }
}

@Suite("Presets, watchlist and commands")
struct PersonalizationTests {
    private func item(_ name: String, _ section: CleanSection, _ safety: Safety) -> CleanItem {
        CleanItem(candidate: CleanCandidate(path: "/tmp/\(name)", label: name, detail: "", section: section, safety: safety), size: 1)
    }

    @Test func presetsSelectTheRightItems() {
        let items = [
            item("browser", .browsers, .safe), item("derived", .developer, .safe), item("archives", .developer, .review),
            item("prefs", .leftovers, .review), item("backups", .storage, .manual),
        ]
        #expect(CleanPreset.recommended.selection(from: items) == ["/tmp/browser", "/tmp/derived"])
        #expect(CleanPreset.light.selection(from: items) == ["/tmp/browser"])
        #expect(CleanPreset.developer.selection(from: items) == ["/tmp/browser", "/tmp/derived", "/tmp/archives"])
        #expect(CleanPreset.everything.selection(from: items).count == 4)
        #expect(CleanPreset.none.selection(from: items).isEmpty)
    }

    @Test func customFoldersAreReviewOnly() throws {
        let folder = try TemporaryFolder()
        try folder.file("old.zip", bytes: 10)
        let candidates = CleanCatalog.discover(fullDiskAccess: false, customFolders: [CustomCleanFolder(path: folder.path)])
        let mine = try #require(candidates.first { $0.path == folder.path })
        #expect(mine.section == .custom)
        #expect(mine.safety == .review)
        #expect(mine.contentsOnly)
    }

    @Test func putBackRestoresTrashedItems() throws {
        let folder = try TemporaryFolder()
        let original = try folder.file("cache/data.bin", bytes: 10)
        let parked = folder.path + "/trash-data.bin"
        try FileManager.default.moveItem(atPath: original, toPath: parked)
        let failed = Remover.putBack([RestorableItem(originalPath: original, trashedPath: parked, size: 10)])
        #expect(failed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: original))
        // An item whose place is taken again stays where it is.
        let taken = try folder.file("taken.bin", bytes: 1)
        let other = try folder.file("other.bin", bytes: 1)
        #expect(Remover.putBack([RestorableItem(originalPath: taken, trashedPath: other, size: 1)]).count == 1)
    }

    private func process(_ name: String, cpu: Double, memory: Int64 = 0, pid: Int32 = 1) -> ProcessRow {
        ProcessRow(pid: pid, name: name, path: "/x/\(name)", user: "me", cpu: cpu, memory: memory)
    }

    @Test func watchRulesNeedSustainedBreachesAndCoolDown() {
        var evaluator = WatchEvaluator()
        let rule = WatchRule(processName: "Builder", metric: .cpu, threshold: 80, minutes: 5)
        let start = Date()
        let busy = [process("Builder", cpu: 150), process("builder", cpu: 20, pid: 2)]
        #expect(evaluator.update(rules: [rule], processes: busy, now: start).isEmpty)
        let breach = evaluator.update(rules: [rule], processes: busy, now: start.addingTimeInterval(301))
        #expect(breach.count == 1)
        #expect(breach.first?.process.cpu == 150)
        #expect(evaluator.update(rules: [rule], processes: busy, now: start.addingTimeInterval(400)).isEmpty)
        // Dropping below the limit resets the timer.
        #expect(evaluator.update(rules: [rule], processes: [process("Builder", cpu: 10)], now: start.addingTimeInterval(500)).isEmpty)
        #expect(evaluator.update(rules: [rule], processes: busy, now: start.addingTimeInterval(600)).isEmpty)
        let memory = WatchRule(processName: "Hog", metric: .memory, threshold: 1000, minutes: 1)
        #expect(evaluator.update(rules: [memory], processes: [process("Hog", cpu: 0, memory: 2_000_000_000)], now: start).isEmpty)
        #expect(evaluator.update(rules: [memory], processes: [process("Hog", cpu: 0, memory: 2_000_000_000)], now: start.addingTimeInterval(61)).count == 1)
    }

    @Test func fuzzyMatchRanksWordStartsAndConsecutiveLetters() {
        #expect(FuzzyMatch.score("xyz", in: "Scan for junk") == nil)
        #expect(FuzzyMatch.score("", in: "anything") == 0)
        let ranked = FuzzyMatch.rank(["Show next tab", "Scan for junk", "Clean Screen"], query: "scan") { [$0] }
        #expect(ranked.first == "Scan for junk")
        #expect(FuzzyMatch.rank(["a", "b"], query: " ") { [$0] } == ["a", "b"])
    }

    @Test func keyCombosNeedTwoModifiersForGlobalUse() {
        let palette = KeyCombo(keyCode: 40, modifiers: KeyCombo.command | KeyCombo.shift, key: "k")
        #expect(palette.isValidGlobal)
        #expect(palette.display == "⇧⌘K")
        #expect(!KeyCombo(keyCode: 40, modifiers: KeyCombo.command, key: "k").isValidGlobal)
        #expect(KeyCombo(keyCode: 1, modifiers: KeyCombo.control | KeyCombo.option | KeyCombo.shift | KeyCombo.command, key: "s").display == "⌃⌥⇧⌘S")
    }
}
