import AppKit
import Artwork
import CfmacCore
import FanService
import Foundation
import ServiceManagement
import SoundKit

enum MenuBarContent: String, CaseIterable, Identifiable, Codable {
    case runner, metric, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .runner: "Icon"
        case .metric: "Live data"
        case .both: "Icon and data"
        }
    }
}

enum MenuBarMetric: String, CaseIterable, Identifiable, Codable {
    case cpu, memory, gpu, temperature, battery, disk, network, fan
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: "CPU usage"
        case .memory: "Memory usage"
        case .gpu: "GPU usage"
        case .temperature: "CPU temperature"
        case .battery: "Battery level"
        case .disk: "Free disk space"
        case .network: "Download speed"
        case .fan: "Fan speed"
        }
    }
}

/// What makes the menu bar runner run faster.
enum RunnerSpeedSource: String, CaseIterable, Identifiable, Codable {
    case cpu, gpu, network, fan
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: "CPU load"
        case .gpu: "GPU load"
        case .network: "Network activity"
        case .fan: "Fan speed"
        }
    }
}

enum KeepAwakeMode: String, CaseIterable, Identifiable, Codable {
    case displayOnly, displayAndSystem, systemOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .displayOnly: "Screen only"
        case .displayAndSystem: "Screen and tasks"
        case .systemOnly: "Tasks only"
        }
    }
    var detail: String {
        switch self {
        case .displayOnly: "Screen stays on; sleep otherwise follows System Settings"
        case .displayAndSystem: "Screen stays on and the Mac keeps working"
        case .systemOnly: "Screen can turn off; tasks keep running"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, dark, light
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Places a planet appears.
enum HeroSlot: String, CaseIterable, Identifiable, Codable {
    case clean, optimize, analyze, health
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clean: "Clean"
        case .optimize: "Optimize"
        case .analyze: "Analyze"
        case .health: "Status › Health"
        }
    }
    var defaultPlanet: Planet {
        switch self {
        case .clean: .earth
        case .optimize: .mercury
        case .analyze: .jupiter
        case .health: .sun
        }
    }
}

enum StatusCard: String, CaseIterable, Identifiable, Codable {
    case health, cpu, gpu, memory, battery, disk, network, fan
    var id: String { rawValue }
    var title: String {
        switch self {
        case .health: "Health"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .battery: "Battery"
        case .disk: "Free space"
        case .network: "Network"
        case .fan: "Fan"
        }
    }
}

/// Actions that can have a global keyboard shortcut.
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case showWindow, commandPalette, scan, keepAwake, cleanScreen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .showWindow: "Show the cfmac window"
        case .commandPalette: "Open the command palette"
        case .scan: "Scan for junk"
        case .keepAwake: "Toggle Keep Screen On"
        case .cleanScreen: "Start Clean Screen"
        }
    }
}

/// Preferences, persisted in UserDefaults. The single owner of every key.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key: String {
        case deletePermanently, showMenuBar, menuBarContent, menuBarMetrics, lowDiskAlert, removeAppData
        case keepAwakeMode, cleanScreenSeconds, ignoredUpdates, protectedPaths, acceptedTermsVersion
        case fanControlEnabled, fanAutoReturn, fanCurve, fanQuietHours, fanQuietCap, appFanRules
        case soundChoice, soundVolume, soundPerJob, jobSounds, savedSounds, soundQuietHours, soundsOnlyInBackground
        case runner, runnerSpeedSource, customFolders, cleanPreset, autoClean
        case appearance, tabTints, useSystemAccent, heroPlanets, planetSpeed, reduceMotion
        case statusCards, hiddenStatusCards, watchRules, shortcuts
    }

    private let defaults = UserDefaults.standard

    // General
    @Published var deletePermanently: Bool { didSet { store(deletePermanently, .deletePermanently) } }
    @Published var lowDiskAlert: Bool { didSet { store(lowDiskAlert, .lowDiskAlert) } }
    @Published var removeAppData: Bool { didSet { store(removeAppData, .removeAppData) } }
    @Published var keepAwakeMode: KeepAwakeMode { didSet { store(keepAwakeMode, .keepAwakeMode) } }
    @Published var cleanScreenSeconds: Int { didSet { store(cleanScreenSeconds, .cleanScreenSeconds) } }
    @Published var acceptedTermsVersion: Int { didSet { store(acceptedTermsVersion, .acceptedTermsVersion) } }
    @Published private(set) var ignoredUpdates: Set<String> { didSet { store(ignoredUpdates, .ignoredUpdates) } }
    @Published private(set) var protectedPaths: [String] { didSet { store(protectedPaths, .protectedPaths) } }

    // Menu bar
    @Published var showMenuBar: Bool { didSet { store(showMenuBar, .showMenuBar) } }
    @Published var menuBarContent: MenuBarContent { didSet { store(menuBarContent, .menuBarContent) } }
    /// Up to three live numbers, in order.
    @Published var menuBarMetrics: [MenuBarMetric] { didSet { store(Array(menuBarMetrics.prefix(3)), .menuBarMetrics) } }
    @Published var runner: Runner { didSet { store(runner.rawValue, .runner) } }
    @Published var runnerSpeedSource: RunnerSpeedSource { didSet { store(runnerSpeedSource, .runnerSpeedSource) } }

    // Fan (off until the user turns it on)
    @Published var fanControlEnabled: Bool { didSet { store(fanControlEnabled, .fanControlEnabled) } }
    @Published var fanAutoReturn: Bool { didSet { store(fanAutoReturn, .fanAutoReturn) } }
    @Published var fanCurve: FanCurve { didSet { store(fanCurve, .fanCurve) } }
    @Published var fanQuietHours: QuietHours { didSet { store(fanQuietHours, .fanQuietHours) } }
    /// Highest Cool-mode speed during quiet hours, 0...1.
    @Published var fanQuietCap: Double { didSet { store(fanQuietCap, .fanQuietCap) } }
    @Published var appFanRules: [AppFanRule] { didSet { store(appFanRules, .appFanRules) } }

    // Sounds
    @Published var soundChoice: SoundChoice { didSet { store(soundChoice, .soundChoice) } }
    @Published var soundVolume: Double { didSet { store(soundVolume, .soundVolume) } }
    @Published var soundPerJob: Bool { didSet { store(soundPerJob, .soundPerJob) } }
    @Published var jobSounds: [SoundJob: SoundChoice] { didSet { store(jobSounds, .jobSounds) } }
    /// Imported files and typed lines the user kept.
    @Published var savedSounds: [SoundChoice] { didSet { store(savedSounds, .savedSounds) } }
    @Published var soundQuietHours: QuietHours { didSet { store(soundQuietHours, .soundQuietHours) } }
    @Published var soundsOnlyInBackground: Bool { didSet { store(soundsOnlyInBackground, .soundsOnlyInBackground) } }

    // Cleaning
    @Published var customFolders: [CustomCleanFolder] { didSet { store(customFolders, .customFolders) } }
    @Published var cleanPreset: CleanPreset { didSet { store(cleanPreset, .cleanPreset) } }
    @Published var autoClean: AutoCleanPolicy { didSet { store(autoClean, .autoClean) } }

    // Appearance
    @Published var appearance: AppearanceMode { didSet { store(appearance, .appearance) } }
    /// Custom base colors (0xRRGGBB) per tab; missing tabs use their default color.
    @Published var tabTints: [String: UInt32] { didSet { store(tabTints, .tabTints) } }
    @Published var useSystemAccent: Bool { didSet { store(useSystemAccent, .useSystemAccent) } }
    @Published var heroPlanets: [HeroSlot: Planet] { didSet { store(heroPlanets, .heroPlanets) } }
    /// Rotation speed multiplier, 0.25...3.
    @Published var planetSpeed: Double { didSet { store(planetSpeed, .planetSpeed) } }
    @Published var reduceMotion: Bool { didSet { store(reduceMotion, .reduceMotion) } }
    @Published var statusCards: [StatusCard] { didSet { store(statusCards, .statusCards) } }
    @Published var hiddenStatusCards: Set<StatusCard> { didSet { store(hiddenStatusCards, .hiddenStatusCards) } }

    // Watchlist and shortcuts
    @Published var watchRules: [WatchRule] { didSet { store(watchRules, .watchRules) } }
    @Published var shortcuts: [ShortcutAction: KeyCombo] { didSet { store(shortcuts, .shortcuts) } }

    private init() {
        func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
            guard let data = UserDefaults.standard.data(forKey: key.rawValue), let decoded = try? JSONDecoder().decode(T.self, from: data) else {
                return fallback
            }
            return decoded
        }
        deletePermanently = value(.deletePermanently, false)
        lowDiskAlert = value(.lowDiskAlert, true)
        removeAppData = value(.removeAppData, true)
        keepAwakeMode = value(.keepAwakeMode, .displayOnly)
        cleanScreenSeconds = value(.cleanScreenSeconds, 60)
        acceptedTermsVersion = value(.acceptedTermsVersion, 0)
        ignoredUpdates = value(.ignoredUpdates, [])
        protectedPaths = value(.protectedPaths, [])
        showMenuBar = value(.showMenuBar, true)
        menuBarContent = value(.menuBarContent, .both)
        menuBarMetrics = value(.menuBarMetrics, [.cpu])
        runner = Runner(rawValue: value(.runner, Runner.cat.rawValue)) ?? .cat
        runnerSpeedSource = value(.runnerSpeedSource, .cpu)
        fanControlEnabled = value(.fanControlEnabled, false)
        fanAutoReturn = value(.fanAutoReturn, true)
        fanCurve = value(.fanCurve, .standard)
        fanQuietHours = value(.fanQuietHours, QuietHours())
        fanQuietCap = value(.fanQuietCap, 0.5)
        appFanRules = value(.appFanRules, [])
        soundChoice = value(.soundChoice, .builtIn(.chime))
        soundVolume = value(.soundVolume, 0.8)
        soundPerJob = value(.soundPerJob, false)
        jobSounds = value(.jobSounds, [:])
        savedSounds = value(.savedSounds, [])
        soundQuietHours = value(.soundQuietHours, QuietHours())
        soundsOnlyInBackground = value(.soundsOnlyInBackground, false)
        customFolders = value(.customFolders, [])
        cleanPreset = value(.cleanPreset, .recommended)
        autoClean = value(.autoClean, AutoCleanPolicy())
        appearance = value(.appearance, .dark)
        tabTints = value(.tabTints, [:])
        useSystemAccent = value(.useSystemAccent, false)
        heroPlanets = value(.heroPlanets, [:])
        planetSpeed = value(.planetSpeed, 1)
        reduceMotion = value(.reduceMotion, false)
        statusCards = value(.statusCards, StatusCard.allCases)
        hiddenStatusCards = value(.hiddenStatusCards, [])
        watchRules = value(.watchRules, [])
        shortcuts = value(.shortcuts, [:])
        // Cards added in later versions appear at the end.
        statusCards += StatusCard.allCases.filter { !statusCards.contains($0) }
    }

    // MARK: Derived values

    var removalMode: RemovalMode { deletePermanently ? .deletePermanently : .moveToTrash }
    var protectedSet: Set<String> { Set(protectedPaths) }

    func planet(for slot: HeroSlot) -> Planet { heroPlanets[slot] ?? slot.defaultPlanet }

    /// The sound for a finished job, honoring per-job choices.
    func sound(for job: SoundJob) -> SoundChoice {
        soundPerJob ? (jobSounds[job] ?? soundChoice) : soundChoice
    }

    /// Reduce Motion from either cfmac or the macOS accessibility setting.
    var motionReduced: Bool { reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Mutations

    func protect(_ path: String) {
        if !protectedPaths.contains(path) { protectedPaths.append(path) }
    }

    func unprotect(_ path: String) {
        protectedPaths.removeAll { $0 == path }
    }

    func ignoreUpdate(_ id: String) {
        ignoredUpdates.insert(id)
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("cfmac: could not change launch at login: \(error.localizedDescription)")
            }
        }
    }

    private func store<T: Encodable>(_ value: T, _ key: Key) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key.rawValue) }
    }
}

/// Lifetime totals for the menu bar footer and the stats card. Kept only in local preferences.
@MainActor
final class UsageStats: ObservableObject {
    static let shared = UsageStats()
    private let defaults = UserDefaults.standard

    @Published private(set) var bytesCleaned: Int64
    @Published private(set) var cleanRuns: Int
    @Published private(set) var optimizeRuns: Int
    @Published private(set) var appsUninstalled: Int
    @Published private(set) var lastClean: Date?
    let firstUse: Date

    private init() {
        bytesCleaned = Int64(defaults.integer(forKey: "stats.bytesCleaned"))
        cleanRuns = defaults.integer(forKey: "stats.cleanRuns")
        optimizeRuns = defaults.integer(forKey: "stats.optimizeRuns")
        appsUninstalled = defaults.integer(forKey: "stats.appsUninstalled")
        lastClean = defaults.object(forKey: "stats.lastClean") as? Date
        if let first = defaults.object(forKey: "stats.firstUse") as? Date {
            firstUse = first
        } else {
            firstUse = Date()
            defaults.set(firstUse, forKey: "stats.firstUse")
        }
    }

    func recordClean(_ bytes: Int64) {
        bytesCleaned += bytes
        cleanRuns += 1
        lastClean = Date()
        defaults.set(Int(bytesCleaned), forKey: "stats.bytesCleaned")
        defaults.set(cleanRuns, forKey: "stats.cleanRuns")
        defaults.set(lastClean, forKey: "stats.lastClean")
    }

    func recordOptimize() {
        optimizeRuns += 1
        defaults.set(optimizeRuns, forKey: "stats.optimizeRuns")
    }

    func recordUninstall(count: Int) {
        appsUninstalled += count
        defaults.set(appsUninstalled, forKey: "stats.appsUninstalled")
    }
}
