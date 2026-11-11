import AppKit
import Combine
import SwiftUI

@main
struct CfmacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Shared objects are held, not observed: observing them here would rebuild every
    // scene and the main menu whenever a live reading changes.
    private let models = AppModels.shared

    var body: some Scene {
        Window(AppInfo.name, id: WindowID.main) {
            ContentView().environmentModels(models)
        }
        .defaultSize(width: 1200, height: 772)
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(router: models.router, awake: models.awake) }

        Window("About \(AppInfo.name)", id: WindowID.about) {
            AboutView().environmentModels(models)
        }
        .windowResizability(.contentSize)

        WindowGroup(id: WindowID.legal, for: LegalDocument.self) { $document in
            LegalView(document: document ?? .terms)
        }
        .defaultSize(width: 640, height: 720)

        Settings {
            SettingsView().environmentModels(models)
        }
    }
}

/// Every long-lived model, created once.
@MainActor
final class AppModels {
    static let shared = AppModels()

    let settings = AppSettings.shared
    let stats = UsageStats.shared
    let monitor = SystemMonitor.shared
    let fan = FanController.shared
    let awake = KeepAwake.shared
    let router = Router()
    let clean = CleanModel()
    let apps = AppsModel()
    let optimize = OptimizeModel()
    let analyze = AnalyzeModel()
    let autoCleaner = AutoCleaner.shared
}

extension View {
    func environmentModels(_ models: AppModels) -> some View {
        environmentObject(models.settings)
            .environmentObject(models.stats)
            .environmentObject(models.monitor)
            .environmentObject(models.fan)
            .environmentObject(models.awake)
            .environmentObject(models.router)
            .environmentObject(models.clean)
            .environmentObject(models.apps)
            .environmentObject(models.optimize)
            .environmentObject(models.analyze)
            .environmentObject(models.autoCleaner)
    }
}

@MainActor
final class Router: ObservableObject {
    @Published var tab: AppTab = .clean
    @Published var showsDoctor = false
    @Published var showsPalette = false
    @Published var showsStatsCard = false

    func step(_ offset: Int) {
        let tabs = AppTab.allCases
        let index = tabs.firstIndex(of: tab) ?? 0
        tab = tabs[(index + offset + tabs.count) % tabs.count]
    }
}

struct AppCommands: Commands {
    let router: Router
    @ObservedObject var awake: KeepAwake
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.name)") { openWindow(id: WindowID.about) }
        }
        CommandMenu("Tools") {
            Button("Command Palette…") {
                WindowOpener.showMain()
                router.showsPalette.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)
            Button("Share My Stats…") { router.showsStatsCard = true }
            Divider()
            Button("Run Doctor") { router.showsDoctor = true }
            Button(awake.isActive ? "Stop Keep Screen On" : "Keep Screen On") {
                awake.isActive ? awake.stop() : awake.start(minutes: nil)
            }
            Button("Clean Screen") { CleanScreen.shared.start() }
                .keyboardShortcut("l", modifiers: [.command, .control, .option])
        }
        CommandGroup(after: .toolbar) {
            Button("Show Previous Tab") { withAnimation(Motion.tab) { router.step(-1) } }
                .keyboardShortcut("[", modifiers: .command)
            Button("Show Next Tab") { withAnimation(Motion.tab) { router.step(1) } }
                .keyboardShortcut("]", modifiers: .command)
            Divider()
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { withAnimation(Motion.tab) { router.tab = tab } }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        CommandGroup(replacing: .help) {
            Button(LegalDocument.terms.title) { openWindow(id: WindowID.legal, value: LegalDocument.terms) }
            Button(LegalDocument.notices.title) { openWindow(id: WindowID.legal, value: LegalDocument.notices) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleIdentifier != nil { Notifier.requestAuthorization() }
        MainActor.assumeIsolated {
            let models = AppModels.shared
            appearanceSubscription = models.settings.$appearance.sink { mode in
                NSApp.appearance =
                    switch mode {
                    case .system: nil
                    case .dark: NSAppearance(named: .darkAqua)
                    case .light: NSAppearance(named: .aqua)
                    }
            }
            StatusItemController.shared.start(models: models)
            AutoCleaner.shared.start()
            WatchlistMonitor.shared.start()
            HotKeyCenter.shared.reload()
        }
        Task { @MainActor in
            await FanController.shared.checkHelper()
            // Fan control stays off unless the user turned it on and the helper is present.
            if AppSettings.shared.fanControlEnabled, FanController.shared.helperState == .notInstalled {
                AppSettings.shared.fanControlEnabled = false
            }
            FanController.shared.start()
        }
    }

    /// Closing the window keeps cfmac running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { !AppSettings.shared.showMenuBar }
    }

    /// Fans are handed back to macOS before quitting; quitting waits until that is confirmed.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            let restored = await FanController.shared.restoreBeforeQuit()
            if restored || Self.confirmQuitWithoutFanRestore() {
                KeepAwake.shared.release()
                CleanScreen.shared.stop()
                sender.reply(toApplicationShouldTerminate: true)
            } else {
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    @MainActor
    private static func confirmQuitWithoutFanRestore() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Fan restore unconfirmed"
        alert.informativeText =
            "cfmac couldn't confirm that macOS controls the fans again. If you quit anyway, the helper returns them to macOS automatically within 20 seconds."
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
