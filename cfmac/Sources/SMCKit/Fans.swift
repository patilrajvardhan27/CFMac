import Foundation

/// One fan as reported by the SMC.
public struct FanReading: Sendable, Codable, Equatable {
    public let index: Int
    public let rpm: Double
    public let minimum: Double
    public let maximum: Double
    public let target: Double?
    public let mode: Int?

    public init(index: Int, rpm: Double, minimum: Double, maximum: Double, target: Double?, mode: Int?) {
        self.index = index
        self.rpm = rpm
        self.minimum = minimum
        self.maximum = maximum
        self.target = target
        self.mode = mode
    }

    /// Current speed as a share of the fan's maximum (0...1).
    public var speedFraction: Double {
        maximum > 0 ? min(1, max(0, rpm / maximum)) : 0
    }

    /// RPM for a position between this fan's minimum (0) and maximum (1).
    public func rpm(atFraction fraction: Double) -> Double {
        let clamped = min(1, max(0, fraction))
        return (minimum + (maximum - minimum) * clamped).rounded()
    }
}

public enum Fans {
    /// Number of fans; 0 on fanless Macs.
    public static func count(_ smc: SMCConnection) -> Int {
        smc.double("FNum").map { Int($0) } ?? 0
    }

    public static func read(_ smc: SMCConnection) -> [FanReading] {
        (0..<count(smc)).compactMap { index in
            guard let rpmKey = SMCKey.fan(index, "Ac"), let rpm = smc.double(rpmKey) else { return nil }
            let minimum = SMCKey.fan(index, "Mn").flatMap(smc.double) ?? 0
            let maximum = SMCKey.fan(index, "Mx").flatMap(smc.double) ?? 0
            return FanReading(
                index: index,
                rpm: max(0, rpm),
                minimum: minimum,
                maximum: maximum,
                target: SMCKey.fan(index, "Tg").flatMap(smc.double),
                mode: SMCKey.fan(index, "Md").flatMap(smc.double).map { Int($0) }
            )
        }
    }
}

/// Fan modes and the unlock flag exactly as found before cfmac took control.
public struct FanControlSnapshot: Sendable, Equatable {
    public let modes: [Int: Double]
    public let unlock: Double?

    public init(modes: [Int: Double], unlock: Double?) {
        self.modes = modes
        self.unlock = unlock
    }
}

public enum FanControlError: Error, Equatable, Sendable {
    case manualModeRejected(fan: Int)
    case targetNotApplied(fan: Int)
}

/// Writes fan targets. Requires root, so only the privileged helper uses it.
///
/// Apple silicon sequence: set `Ftst` (diagnostic unlock) to 1, switch each fan's
/// `F{n}Md` to manual (1), then write `F{n}Tg`. Restoring writes back the original
/// mode values and unlock flag that were captured before the first change.
public struct FanControl: Sendable {
    private static let manualMode: Double = 1
    private static let unlockKey: SMCKey = "Ftst"

    private let smc: SMCConnection
    private let pause: @Sendable (TimeInterval) -> Void

    public init(smc: SMCConnection, pause: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.smc = smc
        self.pause = pause
    }

    public func capture(fans: [Int]) -> FanControlSnapshot {
        var modes: [Int: Double] = [:]
        for index in fans {
            if let key = SMCKey.fan(index, "Md"), let mode = smc.double(key) { modes[index] = mode }
        }
        return FanControlSnapshot(modes: modes, unlock: smc.double(Self.unlockKey))
    }

    /// Puts each listed fan in manual mode and applies its target RPM.
    public func apply(targets: [Int: Double]) throws {
        if let unlock = smc.double(Self.unlockKey), unlock != 1 {
            try smc.write(Self.unlockKey, number: 1)
        }
        for (index, rpm) in targets.sorted(by: { $0.key < $1.key }) {
            guard let modeKey = SMCKey.fan(index, "Md"), let targetKey = SMCKey.fan(index, "Tg") else { continue }
            try enterManual(index: index, modeKey: modeKey)
            try smc.write(targetKey, number: rpm)
            guard let applied = smc.double(targetKey), abs(applied - rpm) < 1 else {
                throw FanControlError.targetNotApplied(fan: index)
            }
        }
    }

    /// Returns fans to the state captured in `snapshot`.
    public func restore(_ snapshot: FanControlSnapshot) throws {
        var firstError: Error?
        for (index, mode) in snapshot.modes.sorted(by: { $0.key < $1.key }) {
            guard let key = SMCKey.fan(index, "Md") else { continue }
            do { try smc.write(key, number: mode) } catch { firstError = firstError ?? error }
        }
        if let unlock = snapshot.unlock {
            do { try smc.write(Self.unlockKey, number: unlock) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    /// The thermal daemon can hold the mode briefly after unlocking, so retry for up to 3 s.
    private func enterManual(index: Int, modeKey: SMCKey) throws {
        for _ in 0..<20 {
            if smc.double(modeKey) == Self.manualMode { return }
            try? smc.write(modeKey, number: Self.manualMode)
            if smc.double(modeKey) == Self.manualMode { return }
            pause(0.15)
        }
        throw FanControlError.manualModeRejected(fan: index)
    }
}
