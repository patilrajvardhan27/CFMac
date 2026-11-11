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

    /// Temperature (°C) below which a boost ends when "End fan boost after cooling" is on.
    private static let cooledTemperature: Double = 55
    private static let cooledDuration: TimeInterval = 90

    private init() {
        sensors = smc.map(ChipTemperatures.init)
    }

    var hasFans: Bool { !fans.isEmpty }
    var isEnabled: Bool { settings.fanControlEnabled }

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

    // MARK: Sampling (every couple of seconds while Status or the menu bar is visible)

    func refresh() async {
        guard let smc else { return }
        let sensors = sensors
        let (fans, temperatures) = await Task.detached(priority: .utility) {
            (Fans.read(smc), sensors?.read() ?? ThermalReading())
        }.value
        self.fans = fans
        self.temperatures = temperatures
        guard isEnabled, hasFans else { return }
        await updateEffectiveMode()
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
        await updateEffectiveMode()
    }

    /// Applies max(user mode, app rules), renewing the helper lease while not automatic.
    private func updateEffectiveMode() async {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let rule = AppFanRule.strongest(settings.appFanRules, running: running)
        activeRule = rule
        endBoostIfCooled()
        let wanted = max(userMode, rule?.mode ?? .automatic)
        let previous = mode
        mode = wanted
        if wanted == .automatic {
            if previous != .automatic || helperManual { await returnToMacOS(reason: nil) }
            return
        }
        guard helperState == .ready else {
            await checkHelper()
            guard helperState == .ready else {
                mode = .automatic
                message = "The fan helper isn't running. Reinstall it in Settings › Fan."
                return
            }
            return await updateEffectiveMode()
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
                fans = response.fans
            }
        } catch {
            userMode = .automatic
            mode = .automatic
            helperManual = false
            helperState = .unreachable
            message = "Unchanged, the fan helper did not respond"
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
            message = reason ?? "Fans return to macOS automatically"
        }
    }

    /// Returns fans to macOS before quitting. False only when control could not be confirmed.
    func restoreBeforeQuit() async -> Bool {
        guard mode != .automatic || helperManual else { return true }
        userMode = .automatic
        mode = .automatic
        guard let response = try? await send(.automatic) else { return false }
        helperManual = response.manual
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
        for _ in 0..<10 {
            await checkHelper()
            if helperState == .ready { break }
            try? await Task.sleep(for: .milliseconds(300))
        }
        settings.fanControlEnabled = helperState == .ready
        if !settings.fanControlEnabled { message = "The fan helper did not start" }
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
        guard let response = try? await send(.status) else {
            helperState = .unreachable
            return
        }
        helperManual = response.manual
        helperState = response.version == HelperLayout.protocolVersion && HelperInstaller.installedMatchesBundled ? .ready : .outdated
    }

    func reinstall() async {
        _ = await enable()
    }

    private func send(_ request: HelperRequest) async throws -> HelperResponse {
        try await Task.detached(priority: .userInitiated) { try HelperClient.send(request) }.value
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
