import Darwin
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

    private let statePath: String

    init(smc: SMCConnection, statePath: String = HelperLayout.statePath, now: @escaping @Sendable () -> Date = Date.init) {
        self.smc = smc
        self.control = FanControl(smc: smc)
        self.statePath = statePath
        self.now = now
    }

    /// If an earlier run held the fans when it stopped (a crash, or launchd killing it), hand
    /// them back using the state that run saved. The file lives in /var/run, so a reboot,
    /// which also resets the SMC, clears it.
    func recoverFromPreviousRun() {
        queue.sync {
            guard let data = FileManager.default.contents(atPath: statePath) else { return }
            guard let saved = try? JSONDecoder().decode(FanControlSnapshot.self, from: data) else {
                unlink(statePath)
                return
            }
            do {
                try control.restore(saved)
                unlink(statePath)
                log("returned fans to macOS after an unexpected stop")
            } catch {
                // Keep it as the active snapshot so the watchdog keeps retrying.
                snapshot = saved
                leaseExpiry = .distantPast
                log("recovery restore failed: \(error)")
            }
        }
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
        let fans = Fans.read(smc).filter(\.isControllable)
        guard !fans.isEmpty else { return "This Mac has no fans cfmac can control" }
        if snapshot == nil {
            let captured = control.capture(fans: fans.map(\.index))
            snapshot = captured
            persist(captured)
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
            unlink(statePath)
            return nil
        } catch {
            // Keep the snapshot so the watchdog retries.
            log("restore failed: \(error)")
            return "Fans could not be returned to macOS yet"
        }
    }
}

extension FanSupervisor {
    /// Saved before the first change, owner-only, so a restarted helper can undo it.
    fileprivate func persist(_ captured: FanControlSnapshot) {
        guard let data = try? JSONEncoder().encode(captured) else { return }
        let fd = open(statePath, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else {
            log("cannot save fan state: \(errno)")
            return
        }
        defer { close(fd) }
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        fsync(fd)
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("cfmac-helper: \(message)\n".utf8))
}
