import Foundation

/// A daily time window, which may cross midnight (for example 22:00 to 07:00).
public struct QuietHours: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// Minutes after midnight.
    public var start: Int
    public var end: Int

    public init(isEnabled: Bool = false, start: Int = 22 * 60, end: Int = 7 * 60) {
        self.isEnabled = isEnabled
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }

    public static func label(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// When cfmac cleans Safe items on its own. Automatic cleaning always moves items to the
/// Trash, so every run can be undone.
public struct AutoCleanPolicy: Codable, Equatable, Sendable {
    public enum Frequency: String, Codable, CaseIterable, Sendable {
        case off, daily, weekly, monthly

        public var interval: TimeInterval? {
            switch self {
            case .off: nil
            case .daily: 86_400
            case .weekly: 7 * 86_400
            case .monthly: 30 * 86_400
            }
        }

        public var title: String {
            switch self {
            case .off: "Off"
            case .daily: "Every day"
            case .weekly: "Every week"
            case .monthly: "Every month"
            }
        }
    }

    public enum Trigger: Equatable, Sendable {
        case schedule, lowDisk
    }

    public var frequency: Frequency
    /// Clean when free space falls below this many gigabytes; nil turns the trigger off.
    public var lowDiskGigabytes: Int?
    /// Minimum gap between low-disk cleans, so a nearly full disk is not cleaned repeatedly.
    public static let lowDiskCooldown: TimeInterval = 6 * 3600

    public init(frequency: Frequency = .off, lowDiskGigabytes: Int? = nil) {
        self.frequency = frequency
        self.lowDiskGigabytes = lowDiskGigabytes
    }

    public var isEnabled: Bool { frequency != .off || lowDiskGigabytes != nil }

    /// Why a clean is due now, or nil.
    public func trigger(now: Date, lastRun: Date?, freeBytes: Int64) -> Trigger? {
        if let gigabytes = lowDiskGigabytes, freeBytes > 0, freeBytes < Int64(gigabytes) * 1_000_000_000,
            now.timeIntervalSince(lastRun ?? .distantPast) > Self.lowDiskCooldown
        {
            return .lowDisk
        }
        if let interval = frequency.interval, now.timeIntervalSince(lastRun ?? .distantPast) >= interval {
            return .schedule
        }
        return nil
    }
}

/// Lifetime milestones for the shareable stats card.
public enum Milestones {
    public static let thresholds: [Int64] = [1, 5, 10, 25, 50, 100, 250, 500, 1000].map { Int64($0) * 1_000_000_000 }

    /// The largest milestone reached, if any.
    public static func reached(_ bytes: Int64) -> Int64? { thresholds.last { bytes >= $0 } }

    /// The next milestone, and progress toward it (0...1).
    public static func next(after bytes: Int64) -> (target: Int64, progress: Double)? {
        guard let target = thresholds.first(where: { bytes < $0 }) else { return nil }
        let floor = reached(bytes) ?? 0
        return (target, Double(bytes - floor) / Double(target - floor))
    }
}
