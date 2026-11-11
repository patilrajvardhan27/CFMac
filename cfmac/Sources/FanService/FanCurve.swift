import Foundation

/// User-facing fan modes, ordered from least to most cooling.
public enum FanMode: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case automatic, cool, maximum
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Auto"
        case .cool: "Cool"
        case .maximum: "Max"
        }
    }

    private var rank: Int {
        switch self {
        case .automatic: 0
        case .cool: 1
        case .maximum: 2
        }
    }

    public static func < (lhs: FanMode, rhs: FanMode) -> Bool { lhs.rank < rhs.rank }
}

/// Cool mode's temperature-to-speed curve: points joined by straight lines, flat beyond the ends.
public struct FanCurve: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        /// °C
        public var temperature: Double
        /// Position between the fan's minimum (0) and maximum (1) speed.
        public var fraction: Double

        public init(temperature: Double, fraction: Double) {
            self.temperature = temperature
            self.fraction = fraction
        }
    }

    public static let temperatureRange: ClosedRange<Double> = 30...100
    public static let standard = FanCurve(points: [
        Point(temperature: 45, fraction: 0.3), Point(temperature: 60, fraction: 0.45),
        Point(temperature: 75, fraction: 0.7), Point(temperature: 88, fraction: 1),
    ])

    /// Always sorted by temperature, within range.
    public private(set) var points: [Point]

    public init(points: [Point]) {
        self.points =
            points
            .map {
                Point(
                    temperature: min(Self.temperatureRange.upperBound, max(Self.temperatureRange.lowerBound, $0.temperature)),
                    fraction: min(1, max(0, $0.fraction)))
            }
            .sorted { $0.temperature < $1.temperature }
        if self.points.isEmpty { self.points = Self.standard.points }
    }

    /// Speed position for `temperature` (O(points)).
    public func fraction(at temperature: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 1 }
        if temperature <= first.temperature { return first.fraction }
        if temperature >= last.temperature { return last.fraction }
        for (lower, upper) in zip(points, points.dropFirst()) where temperature <= upper.temperature {
            let span = max(0.001, upper.temperature - lower.temperature)
            return lower.fraction + (upper.fraction - lower.fraction) * (temperature - lower.temperature) / span
        }
        return last.fraction
    }

    /// `nil` means macOS should control the fans. Without a reading, Cool errs toward cooling.
    public func fraction(for mode: FanMode, temperature: Double?, cap: Double? = nil) -> Double? {
        switch mode {
        case .automatic: return nil
        case .maximum: return 1
        case .cool:
            let wanted = temperature.map(fraction(at:)) ?? 1
            return cap.map { min(wanted, $0) } ?? wanted
        }
    }

    /// Returns a copy with point `index` moved, keeping points in temperature order.
    public func moving(_ index: Int, to point: Point) -> FanCurve {
        guard points.indices.contains(index) else { return self }
        var updated = points
        let lower = index > 0 ? updated[index - 1].temperature + 1 : Self.temperatureRange.lowerBound
        let upper = index < updated.count - 1 ? updated[index + 1].temperature - 1 : Self.temperatureRange.upperBound
        updated[index] = Point(temperature: min(upper, max(lower, point.temperature)), fraction: point.fraction)
        return FanCurve(points: updated)
    }
}

/// "While this app runs, use at least this mode."
public struct AppFanRule: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public let appName: String
    public var mode: FanMode

    public init(bundleIdentifier: String, appName: String, mode: FanMode) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.mode = mode
    }

    /// The strongest mode requested by a running app, with the app that asked for it.
    public static func strongest(_ rules: [AppFanRule], running: Set<String>) -> AppFanRule? {
        rules.filter { $0.mode != .automatic && running.contains($0.bundleIdentifier) }.max { $0.mode < $1.mode }
    }
}
