import AppKit
import CfmacCore
import Combine

/// Applies Watchlist rules to each process sample. Costs O(processes + rules) per sample and
/// keeps no history beyond "over the limit since" per rule.
@MainActor
final class WatchlistMonitor {
    static let shared = WatchlistMonitor()

    private var evaluator = WatchEvaluator()
    private var subscriptions: Set<AnyCancellable> = []
    private var isSampling = false

    func start() {
        guard subscriptions.isEmpty else { return }
        let settings = AppSettings.shared
        // Sample only while there is something to watch.
        settings.$watchRules
            .map { rules in rules.contains { $0.isEnabled && !$0.processName.isEmpty } }
            .removeDuplicates()
            .sink { [weak self] active in MainActor.assumeIsolated { self?.setSampling(active) } }
            .store(in: &subscriptions)
        SystemMonitor.shared.$snapshot
            .map(\.processes)
            .removeDuplicates()
            .sink { [weak self] processes in MainActor.assumeIsolated { self?.evaluate(processes) } }
            .store(in: &subscriptions)
    }

    private func setSampling(_ active: Bool) {
        guard active != isSampling else { return }
        isSampling = active
        active ? SystemMonitor.shared.retain() : SystemMonitor.shared.release()
    }

    private func evaluate(_ processes: [ProcessRow]) {
        guard isSampling, !processes.isEmpty else { return }
        for breach in evaluator.update(rules: AppSettings.shared.watchRules, processes: processes, now: Date()) {
            act(on: breach)
        }
    }

    private func act(on breach: WatchEvaluator.Breach) {
        let rule = breach.rule
        let amount = rule.metric == .cpu ? "\(Int(breach.value))% CPU" : Format.bytes(breach.process.memory)
        let minutes = "\(Int(rule.minutes)) min"
        guard rule.action == .quit else {
            Notifier.post(title: "\(breach.process.name) is busy", body: "It has used \(amount) for over \(minutes).")
            return
        }
        // Ask apps to quit normally; other processes get a polite SIGTERM after a PID check.
        if let app = NSRunningApplication(processIdentifier: breach.process.pid) {
            app.terminate()
        } else {
            _ = ProcessList.signal(breach.process, force: false)
        }
        Notifier.post(title: "Quit \(breach.process.name)", body: "It used \(amount) for over \(minutes), as your Watchlist rule asks.")
    }
}
