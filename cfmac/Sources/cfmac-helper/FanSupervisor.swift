import FanService
import Foundation
import SMCKit

/// Owns manual fan control. All state lives on `queue`, so requests, the lease
/// watchdog and signal handling never race.
final class FanSupervisor: @unchecked Sendable {
    private let smc: SMCConnection
    private let control: FanControl
    private let queue = DispatchQueue(label: "\(HelperLayout.label).fans")
    private let now: @Sendable () -> Date

    /// Captured before the first manual change; non-nil while cfmac holds control.
    private var snapshot: FanControlSnapshot?
    private var leaseExpiry = Date.distantPast
    private var watchdog: DispatchSourceTimer?

    init(smc: SMCConnection, now: @escaping @Sendable () -> Date = Date.init) {
        self.smc = smc
        self.control = FanControl(smc: smc)
        self.now = now
    }

    func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [unowned self] in
            if snapshot != nil, now() > leaseExpiry {
                log("lease expired, returning fans to macOS")
                restoreLocked()
            }
        }
        timer.resume()
        watchdog = timer
    }

    func handle(_ request: HelperRequest) -> HelperResponse {
        queue.sync {
            var error: String?
            switch request {
            case .status:
                break
            case .manual(let fraction):
                error = applyLocked(fraction: fraction)
            case .automatic:
                error = restoreLocked()
            }
            return HelperResponse(fans: Fans.read(smc), manual: snapshot != nil, error: error)
        }
    }

    /// Used on shutdown signals.
    func restoreAll() {
        queue.sync { _ = restoreLocked() }
    }

    private func applyLocked(fraction: Double) -> String? {
        guard fraction.isFinite else { return "Invalid fan speed" }
        let fans = Fans.read(smc)
        guard !fans.isEmpty else { return "This Mac has no fans" }
        if snapshot == nil {
            snapshot = control.capture(fans: fans.map(\.index))
        }
        leaseExpiry = now().addingTimeInterval(HelperLayout.leaseSeconds)
        let targets = Dictionary(uniqueKeysWithValues: fans.map { ($0.index, $0.rpm(atFraction: fraction)) })
        do {
            try control.apply(targets: targets)
            return nil
        } catch {
            log("apply failed: \(error)")
            restoreLocked()
            return "macOS kept control of the fans"
        }
    }

    @discardableResult
    private func restoreLocked() -> String? {
        guard let saved = snapshot else { return nil }
        do {
            try control.restore(saved)
            snapshot = nil
            return nil
        } catch {
            // Keep the snapshot so the watchdog retries.
            log("restore failed: \(error)")
            return "Fans could not be returned to macOS yet"
        }
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("cfmac-helper: \(message)\n".utf8))
}
