import AppKit
import Artwork
import CfmacCore
import Combine
import SwiftUI

/// The menu bar item: an animated runner (faster as its chosen source gets busier) plus up
/// to three live numbers, opening the status panel in a popover.
///
/// It is built on `NSStatusItem` rather than SwiftUI's `MenuBarExtra`: changing a
/// `MenuBarExtra` label rebuilds the app's scenes and main menu, which is far too costly
/// for an animation that redraws many times a second.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var frames: [NSImage] = []
    private var frameIndex = 0
    private var frameTimer: Timer?
    private var subscriptions: Set<AnyCancellable> = []
    private var models: AppModels?
    private static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)

    func start(models: AppModels) {
        self.models = models
        popover.behavior = .transient
        popover.animates = !models.settings.motionReduced
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel().environmentModels(models))

        let settings = models.settings
        settings.$showMenuBar
            .removeDuplicates()
            .sink { [weak self] visible in MainActor.assumeIsolated { self?.setVisible(visible) } }
            .store(in: &subscriptions)
        settings.$runner
            .removeDuplicates()
            .sink { [weak self] runner in MainActor.assumeIsolated { self?.load(runner) } }
            .store(in: &subscriptions)
        models.monitor.$snapshot
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateTitle() } }
            .store(in: &subscriptions)
        Publishers.Merge4(
            settings.$menuBarContent.map { _ in () },
            settings.$menuBarMetrics.map { _ in () },
            settings.$reduceMotion.map { _ in () },
            models.awake.$isActive.map { _ in () }
        )
        .sink { [weak self] in MainActor.assumeIsolated { self?.refreshAll() } }
        .store(in: &subscriptions)
    }

    private func setVisible(_ visible: Bool) {
        guard visible != (item != nil), let models else { return }
        if visible {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.target = self
            statusItem.button?.action = #selector(togglePopover(_:))
            statusItem.button?.imagePosition = .imageLeading
            item = statusItem
            models.monitor.retain()
            refreshAll()
        } else {
            frameTimer?.invalidate()
            frameTimer = nil
            popover.performClose(nil)
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            models.monitor.release()
        }
    }

    private func load(_ runner: Runner) {
        frames = runner.frames()
        frameIndex = 0
        refreshAll()
    }

    private func refreshAll() {
        frameTimer?.invalidate()
        frameTimer = nil
        advanceFrame()
        updateTitle()
    }

    private var showsRunner: Bool { models?.settings.menuBarContent != .metric && !frames.isEmpty }

    private func advanceFrame() {
        guard let button = item?.button, let models else { return }
        guard showsRunner else {
            button.image = nil
            return
        }
        button.image = frames[frameIndex % frames.count]
        // Reduce Motion: a still runner, and no timer at all.
        guard !models.settings.motionReduced else { return }
        frameIndex = (frameIndex + 1) % frames.count
        frameTimer = Timer.scheduledTimer(withTimeInterval: RunnerFrames.frameInterval(load: runnerLoad(models)), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFrame() }
        }
    }

    private func runnerLoad(_ models: AppModels) -> Double {
        let snapshot = models.monitor.snapshot
        switch models.settings.runnerSpeedSource {
        case .cpu: return snapshot.cpu
        case .gpu: return snapshot.gpu ?? 0
        case .network: return min(1, (snapshot.network.download + snapshot.network.upload) / 5_000_000)
        case .fan: return models.fan.fans.map(\.speedFraction).max() ?? 0
        }
    }

    private func updateTitle() {
        guard let button = item?.button, let models else { return }
        var parts = models.settings.menuBarContent == .runner ? [] : models.settings.menuBarMetrics.map { text(for: $0, models) }
        if models.awake.isActive { parts.insert("☕︎", at: 0) }
        let text = parts.joined(separator: "  ")
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [.font: Self.titleFont])
        if !showsRunner, text.isEmpty {
            button.image = NSImage(systemSymbolName: "globe.americas.fill", accessibilityDescription: AppInfo.name)
        }
        button.setAccessibilityLabel("\(AppInfo.name) \(text)")
    }

    private func text(for metric: MenuBarMetric, _ models: AppModels) -> String {
        let snapshot = models.monitor.snapshot
        switch metric {
        case .cpu: return "\(Format.percent(snapshot.cpu))%"
        case .memory: return "\(Format.percent(snapshot.memory.fraction))%"
        case .gpu: return snapshot.gpu.map { "\(Format.percent($0))%" } ?? "–"
        case .temperature: return models.fan.temperatures.cpu.map { "\(Int($0.rounded()))°" } ?? "–"
        case .battery: return snapshot.battery.map { "\($0.percent)%" } ?? "AC"
        case .disk: return Format.bytes(snapshot.volume.available)
        case .network: return "↓" + Format.rate(snapshot.network.download)
        case .fan: return models.fan.fans.map(\.rpm).max().map { "\(Int($0))rpm" } ?? "–"
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() {
        popover.performClose(nil)
    }
}

/// Opens SwiftUI windows from AppKit code (the status panel lives outside any scene).
@MainActor
enum WindowOpener {
    static var openWindow: OpenWindowAction?

    static func showMain() {
        StatusItemController.shared.closePopover()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(WindowID.main) == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: WindowID.main)
        }
    }
}
