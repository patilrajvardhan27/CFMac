import Foundation

/// Chip temperatures in °C. `nil` when this Mac exposes no matching sensor.
public struct ThermalReading: Sendable, Equatable {
    public var cpu: Double?
    public var cpuPeak: Double?
    public var gpu: Double?

    public init(cpu: Double? = nil, cpuPeak: Double? = nil, gpu: Double? = nil) {
        self.cpu = cpu
        self.cpuPeak = cpuPeak
        self.gpu = gpu
    }
}

/// Reads CPU and GPU die sensors. Keys are discovered once, because their names
/// differ by chip (`Tp`/`Te` cores on Apple silicon, `TC` on Intel, `Tg`/`TG` GPU).
public final class ChipTemperatures: Sendable {
    static let plausibleRange: ClosedRange<Double> = 5...125

    private let smc: SMCConnection
    private let cpuKeys: [SMCKey]
    private let gpuKeys: [SMCKey]

    public init(smc: SMCConnection) {
        self.smc = smc
        let keys = smc.allKeys()
        func sensors(_ prefixes: [String]) -> [SMCKey] {
            keys.filter { key in
                let name = key.description
                guard prefixes.contains(where: name.hasPrefix), let value = smc.double(key) else { return false }
                return Self.plausibleRange.contains(value)
            }
        }
        cpuKeys = sensors(["Tp", "Te", "TC"])
        gpuKeys = sensors(["Tg", "TG"])
    }

    public func read() -> ThermalReading {
        let cpu = values(cpuKeys)
        let gpu = values(gpuKeys)
        return ThermalReading(cpu: Self.mean(cpu), cpuPeak: cpu.max(), gpu: Self.mean(gpu))
    }

    private func values(_ keys: [SMCKey]) -> [Double] {
        keys.compactMap(smc.double).filter(Self.plausibleRange.contains)
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
