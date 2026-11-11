import Foundation

/// "Tell me (or quit it) when this app uses too much CPU or memory for too long."
public struct WatchRule: Codable, Hashable, Identifiable, Sendable {
    public enum Metric: String, Codable, CaseIterable, Sendable {
        case cpu, memory

        public var title: String { self == .cpu ? "CPU" : "Memory" }
        public var unit: String { self == .cpu ? "%" : "MB" }
    }

    public enum Action: String, Codable, CaseIterable, Sendable {
        case notify, quit

        public var title: String { self == .notify ? "Notify me" : "Quit it and notify me" }
    }

    public var id = UUID()
    /// Process name as shown in the Status table.
    public var processName: String
    public var metric: Metric
    /// CPU percent (100 = one busy core) or memory in megabytes.
    public var threshold: Double
    /// How long the limit must be exceeded before acting.
    public var minutes: Double
    public var action: Action
    public var isEnabled = true

    public init(processName: String, metric: Metric = .cpu, threshold: Double = 80, minutes: Double = 5, action: Action = .notify) {
        self.processName = processName
        self.metric = metric
        self.threshold = threshold
        self.minutes = minutes
        self.action = action
    }

    func value(of process: ProcessRow) -> Double {
        metric == .cpu ? process.cpu : Double(process.memory) / 1_048_576
    }
}

/// Tracks how long each rule has been over its limit. Each `update` is O(processes + rules).
public struct WatchEvaluator: Sendable {
    public struct Breach: Equatable, Sendable {
        public let rule: WatchRule
        public let process: ProcessRow
        public let value: Double
    }

    /// Repeat alerts for the same rule no more than once per this interval.
    public static let cooldown: TimeInterval = 30 * 60

    private var overSince: [UUID: Date] = [:]
    private var lastAlert: [UUID: Date] = [:]

    public init() {}

    public mutating func update(rules: [WatchRule], processes: [ProcessRow], now: Date) -> [Breach] {
        // Busiest process per name for each metric, so helpers sharing a name count once.
        var busiestCPU: [String: ProcessRow] = [:]
        var busiestMemory: [String: ProcessRow] = [:]
        busiestCPU.reserveCapacity(processes.count)
        busiestMemory.reserveCapacity(processes.count)
        for process in processes {
            let key = process.name.lowercased()
            if process.cpu > busiestCPU[key]?.cpu ?? -1 { busiestCPU[key] = process }
            if process.memory > busiestMemory[key]?.memory ?? -1 { busiestMemory[key] = process }
        }
        var breaches: [Breach] = []
        for rule in rules where rule.isEnabled {
            let key = rule.processName.lowercased()
            guard let process = rule.metric == .cpu ? busiestCPU[key] : busiestMemory[key], rule.value(of: process) > rule.threshold else {
                overSince[rule.id] = nil
                continue
            }
            let since = overSince[rule.id] ?? now
            overSince[rule.id] = since
            let sustained = now.timeIntervalSince(since) >= rule.minutes * 60
            let cooled = now.timeIntervalSince(lastAlert[rule.id] ?? .distantPast) >= Self.cooldown
            if sustained, cooled {
                lastAlert[rule.id] = now
                breaches.append(Breach(rule: rule, process: process, value: rule.value(of: process)))
            }
        }
        return breaches
    }
}
