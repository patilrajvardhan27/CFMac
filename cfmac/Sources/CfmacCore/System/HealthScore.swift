import Foundation

/// A 0–100 summary of how the Mac is doing: 100 minus one penalty per problem.
public struct HealthScore: Sendable, Equatable {
    public struct Inputs: Sendable, Equatable {
        public var cpu: Double
        public var pressure: MemoryPressure
        public var freeDiskFraction: Double?
        public var batteryHealth: Int?
        public var batteryCycles: Int?
        public var thermalState: ProcessInfo.ThermalState
        public var uptime: TimeInterval

        public init(
            cpu: Double, pressure: MemoryPressure, freeDiskFraction: Double?, batteryHealth: Int?,
            batteryCycles: Int?, thermalState: ProcessInfo.ThermalState, uptime: TimeInterval
        ) {
            self.cpu = cpu
            self.pressure = pressure
            self.freeDiskFraction = freeDiskFraction
            self.batteryHealth = batteryHealth
            self.batteryCycles = batteryCycles
            self.thermalState = thermalState
            self.uptime = uptime
        }
    }

    public struct Penalty: Sendable, Equatable {
        public let reason: String
        public let points: Int
    }

    public let score: Int
    public let penalties: [Penalty]

    public var label: String {
        switch score {
        case 90...: "Excellent"
        case 75..<90: "Good"
        case 55..<75: "Fair"
        default: "Needs Attention"
        }
    }

    /// The most important problem, or a reassuring line when there is none.
    public var headline: String { penalties.max { $0.points < $1.points }?.reason ?? "Current readings normal" }

    public init(_ inputs: Inputs) {
        var penalties: [Penalty] = []
        func penalize(_ points: Int, _ reason: String) { penalties.append(Penalty(reason: reason, points: points)) }

        if inputs.cpu > 0.8 { penalize(15, "CPU load high") } else if inputs.cpu > 0.6 { penalize(5, "CPU load high") }
        switch inputs.pressure {
        case .critical: penalize(25, "Memory pressure")
        case .warning: penalize(10, "Memory pressure")
        case .normal: break
        }
        if let free = inputs.freeDiskFraction {
            if free < 0.1 { penalize(20, "Disk space low") } else if free < 0.2 { penalize(8, "Disk space low") }
        }
        if let health = inputs.batteryHealth, health < 80 { penalize(10, "Battery health low") }
        if let cycles = inputs.batteryCycles, cycles > 1000 { penalize(5, "Battery aging") }
        if inputs.thermalState == .serious || inputs.thermalState == .critical { penalize(15, "Running warm") }
        if inputs.uptime > 14 * 86_400 { penalize(5, "Long time since restart") }

        self.penalties = penalties
        self.score = max(0, 100 - penalties.reduce(0) { $0 + $1.points })
    }
}
