import AppKit
import CfmacCore
import FanService
import Foundation
import SMCKit

/// Fan readings and Auto / Cool / Max control.
///
/// Reading fans and temperatures needs no privileges. Changing speed is opt-in: it stays
/// off until the user turns on fan control, which installs the root helper after showing
/// exactly what will change. The helper holds manual control only while this controller
/// keeps renewing its lease.
///
/// The controller runs its own sampling loop from launch, so the lease is renewed, app rules
/// are applied and the menu bar stays current whichever screen is open, or none.
@MainActor
final class FanController: ObservableObject {
    static let shared = FanController()

    enum HelperState: Equatable {
        case checking, notInstalled, ready, outdated, unreachable
    }

    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var temperatures = ThermalReading()
    /// The mode the user picked.
    @Published private(set) var userMode: FanMode = .automatic
    /// The mode in force: the user's choice, raised by any app rule.
    @Published private(set) var mode: FanMode = .automatic
    /// The app rule currently raising the mode, if any.
    @Published private(set) var activeRule: AppFanRule?
    @Published private(set) var helperState: HelperState = .checking
    @Published private(set) var isWorking = false
    @Published var message: String?
    /// True while the "turn on fan control" sheet is shown.
    @Published var showsEnableSheet = false

    private let smc = try? SMCConnection()
    private let sensors: ChipTemperatures?
    private var cooledSince: Date?
    private var helperManual = false
    private var settings: AppSettings { .shared }

    private var loop: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    /// Keeps App Nap from stretching the loop past the helper's lease while fans are held.
    private var leaseActivity: NSObjectProtocol?
    /// Serializes helper requests; a change requested meanwhile runs right after.
    private var isApplying = false
    private var needsApply = false
    private var pendingUserRequest = false

    /// Temperature (°C) below which a boost ends when "End fan boost after cooling" is on.
    private static let cooledTemperature: Double = 55
    private static let cooledDuration: TimeInterval = 90
    /// Sampling while fans are held or a screen shows fan readings. Well inside the lease.
    private static let activeInterval: TimeInterval = 2
    /// Sampling otherwise, so app rules and the menu bar still react.
    private static let idleInterval: TimeInterval = 5

    private init() {
        sensors = smc.map(ChipTemperatures.init)
    }

    var hasFans: Bool { !fans.isEmpty }
    var isEnabled: Bool { settings.fanControlEnabled }
    private var holdsFans: Bool { mode != .automatic || helperManual }

    var strategyText: String {
        if !isEnabled { return "Fan control is off · Managed by macOS" }
        if let activeRule, mode > userMode { return "\(mode.title) while \(activeRule.appName) runs" }
        switch mode {
        case .automatic: return "Managed by macOS"
        case .cool:
            return settings.fanQuietHours.contains(Date())
                ? "Quiet hours · up to \(Format.percent(settings.fanQuietCap))%" : "Follows your cooling curve"
        case .maximum: return "Holding at maximum"
        }
    }

    // MARK: Sampling loop

    /// Starts sampling for the life of the app. Safe to call more than once.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = self.holdsFans || SystemMonitor.shared.isSampling ? Self.activeInterval : Self.idleInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
        // The SMC may hand fans back to macOS across sleep; reapply at once on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
    }

    func refresh() async {
        guard let smc else { return }
        let sensors = sensors
        let (fans, temperatures) = await Task.detached(priority: .utility) {
            (Fans.read(smc), sensors?.read() ?? ThermalReading())
        }.value
        self.fans = fans
        self.temperatures = temperatures
        guard isEnabled, hasFans else { return }
        await applyEffectiveMode()
    }

    // MARK: Mode changes

    func select(_ newMode: FanMode) async {
        guard isEnabled else {
            showsEnableSheet = true
            return
        }
        guard !isWorking else { return }
        userMode = newMode
        cooledSince = nil
        message = nil
        pendingUserRequest = true
        await applyEffectiveMode()
    }

    /// Runs `updateEffectiveMode` one at a time. A request that arrives while one is in
    /// flight is folded into a single follow-up pass.
    private func applyEffectiveMode() async {
        guard !isApplying else {
            needsApply = true
            return
        }
        isApplying = true
        defer { isApplying = false }
        repeat {
            needsApply = false
            let userInitiated = pendingUserRequest
            pendingUserRequest = false
            await updateEffectiveMode(userInitiated: userInitiated)
        } while needsApply
        updateLeaseActivity()
    }

    /// Applies max(user mode, app rules), renewing the helper lease while not automatic.
    private func updateEffectiveMode(userInitiated: Bool) async {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let rule = AppFanRule.strongest(settings.appFanRules, running: running)
        activeRule = rule
        endBoostIfCooled()
        let wanted = max(userMode, rule?.mode ?? .automatic)
        let previous = mode
        if wanted == .automatic {
            mode = .automatic
            if previous != .automatic || helperManual { await returnToMacOS(reason: nil) }
            return
        }
        if helperState != .ready {
            await checkHelper()
        }
        guard helperState == .ready else {
            helperUnavailable(userInitiated: userInitiated)
            return
        }
        let peak = temperatures.cpuPeak ?? temperatures.cpu
        let cap = settings.fanQuietHours.contains(Date()) ? settings.fanQuietCap : nil
        guard let fraction = settings.fanCurve.fraction(for: wanted, temperature: peak, cap: cap) else { return }
        do {
            let response = try await send(.manual(fraction: fraction))
            helperManual = response.manual
            if let error = response.error {
                userMode = .automatic
                mode = .automatic
                message = "Unchanged, \(error)"
            } else {
                mode = wanted
                if !response.fans.isEmpty { fans = response.fans }
            }
        } catch {
            userMode = .automatic
            mode = .automatic
            helperManual = false
            helperState = .unreachable
            message = Self.unreachableMessage
        }
    }

    private static let unreachableMessage =
        "The fan helper isn't answering. Allow cfmac in System Settings › General › Login Items, or reinstall it in Settings › Fan."

    /// The helper can't take the request: fall back to Auto and say why. An outdated helper
    /// (cfmac was updated) asks once to be updated, when the user picked the mode.
    private func helperUnavailable(userInitiated: Bool) {
        userMode = .automatic
        mode = .automatic
        activeRule = nil
        switch helperState {
        case .outdated:
            message = "cfmac was updated, so its fan helper needs updating too. Approve once to continue."
            if userInitiated { showsEnableSheet = true }
        case .notInstalled:
            message = "The fan helper is not installed. Turn on fan control to install it."
            if userInitiated { showsEnableSheet = true }
        default:
            message = Self.unreachableMessage
        }
    }

    /// "End fan boost after cooling": a user-chosen boost returns to Auto once cool.
    private func endBoostIfCooled() {
        guard settings.fanAutoReturn, userMode != .automatic, let peak = temperatures.cpuPeak ?? temperatures.cpu else {
            cooledSince = nil
            return
        }
        guard peak < Self.cooledTemperature else {
            cooledSince = nil
            return
        }
        let since = cooledSince ?? Date()
        cooledSince = since
        if Date().timeIntervalSince(since) > Self.cooledDuration {
            userMode = .automatic
            cooledSince = nil
            message = "Back to Auto, cooled down"
        }
    }

    private func returnToMacOS(reason: String?) async {
        guard helperManual || helperState == .ready else {
            message = reason ?? message
            return
        }
        do {
            let response = try await send(.automatic)
            helperManual = response.manual
            if let error = response.error { message = error } else if let reason { message = reason }
        } catch {
            // The helper's lease ends manual control on its own within seconds.
            helperManual = false
            message = reason ?? "Fans return to macOS automatically"
        }
    }

    /// Holds a "user initiated" activity while the helper has the fans, so the loop keeps
    /// its pace with the window closed. Idle sleep stays allowed.
    private func updateLeaseActivity() {
        if holdsFans, leaseActivity == nil {
            leaseActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep], reason: "Renewing the fan speed lease")
        } else if !holdsFans, let activity = leaseActivity {
            ProcessInfo.processInfo.endActivity(activity)
            leaseActivity = nil
        }
    }

    /// Returns fans to macOS before quitting. False only when control could not be confirmed.
    func restoreBeforeQuit() async -> Bool {
        loop?.cancel()
        loop = nil
        guard holdsFans else { return true }
        userMode = .automatic
        mode = .automatic
        guard let response = try? await send(.automatic) else { return false }
        helperManual = response.manual
        updateLeaseActivity()
        return !response.manual
    }

    // MARK: Turning fan control on and off

    /// Installs the helper (one administrator prompt) and turns fan control on if that worked.
    func enable() async -> Bool {
        guard let source = HelperInstaller.bundledHelper else {
            message = "The fan helper is missing from this copy of cfmac"
            return false
        }
        isWorking = true
        defer { isWorking = false }
        message = nil
        let result = await HelperInstaller.install(helperSource: source.path)
        guard result.succeeded else {
            message = result.wasCancelledByUser ? "Fan control stays off: the password prompt was cancelled" : "The fan helper could not be installed"
            return false
        }
        // launchd needs a moment to start the helper.
        for _ in 0..<20 {
            await checkHelper()
            if helperState == .ready { break }
            try? await Task.sleep(for: .milliseconds(300))
        }
        settings.fanControlEnabled = helperState == .ready
        if !settings.fanControlEnabled {
            message = "The fan helper did not start. Allow cfmac in System Settings › General › Login Items, then try again."
        }
        return settings.fanControlEnabled
    }

    /// Returns fans to macOS, removes the helper and turns fan control off.
    func disable() async {
        isWorking = true
        defer { isWorking = false }
        userMode = .automatic
        mode = .automatic
        activeRule = nil
        _ = try? await send(.automatic)
        helperManual = false
        updateLeaseActivity()
        let result = await HelperInstaller.uninstall()
        if result.succeeded || !FileManager.default.fileExists(atPath: HelperLayout.launchdPlistPath) {
            settings.fanControlEnabled = false
            message = nil
        } else {
            message = result.wasCancelledByUser ? "Fan control stays on: the password prompt was cancelled" : "The fan helper could not be removed"
        }
        await checkHelper()
    }

    func checkHelper() async {
        guard FileManager.default.fileExists(atPath: HelperLayout.launchdPlistPath) else {
            helperState = .notInstalled
            return
        }
        guard let response = try? await send(.status, timeout: 3) else {
            helperState = .unreachable
            return
        }
        helperManual = response.manual
        let matches = await Task.detached(priority: .utility) { HelperInstaller.installedMatchesBundled }.value
        helperState = response.version == HelperLayout.protocolVersion && matches ? .ready : .outdated
    }

    func reinstall() async {
        _ = await enable()
    }

    private func send(_ request: HelperRequest, timeout: TimeInterval = 8) async throws -> HelperResponse {
        try await Task.detached(priority: .userInitiated) { try HelperClient.send(request, timeout: timeout) }.value
    }
}

/// Installs and removes the privileged helper with one administrator prompt each.
enum HelperInstaller {
    /// The helper binary inside the app bundle (`Contents/Library/LaunchServices`), or next to
    /// the executable when running from a development build.
    static var bundledHelper: URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/cfmac-helper"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("cfmac-helper"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// True when the installed helper is byte-for-byte the one this app ships.
    static var installedMatchesBundled: Bool {
        guard let bundled = bundledHelper,
            let installedData = FileManager.default.contents(atPath: HelperLayout.executablePath),
            let bundledData = FileManager.default.contents(atPath: bundled.path)
        else { return false }
        return installedData == bundledData
    }

    static func install(helperSource: String) async -> ShellResult {
        let script = HelperInstallScript.install(helperSource: helperSource, uid: getuid())
        return await Task.detached {
            Shell.runAsAdministrator(script: script, prompt: "cfmac wants to install its fan helper.")
        }.value
    }

    static func uninstall() async -> ShellResult {
        await Task.detached {
            Shell.runAsAdministrator(script: HelperInstallScript.uninstall(), prompt: "cfmac wants to remove its fan helper.")
        }.value
    }
}
