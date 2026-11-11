import AppKit

/// The bodies cfmac can show, each mapped to a Solar System Scope texture.
public enum Planet: String, CaseIterable, Identifiable, Codable, Sendable {
    case earth, moon, mercury, venus, mars, jupiter, saturn, uranus, neptune, sun

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .earth: "Earth"
        case .moon: "Moon"
        case .mercury: "Mercury"
        case .venus: "Venus"
        case .mars: "Mars"
        case .jupiter: "Jupiter"
        case .saturn: "Saturn"
        case .uranus: "Uranus"
        case .neptune: "Neptune"
        case .sun: "Sun"
        }
    }

    /// Texture file in the artwork folder.
    var textureName: String { "\(rawValue).jpg" }

    /// Used when the texture is not available, so the planet is still recognizable.
    var baseColor: NSColor {
        switch self {
        case .earth: NSColor(red: 0.20, green: 0.42, blue: 0.75, alpha: 1)
        case .moon: NSColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1)
        case .mercury: NSColor(red: 0.55, green: 0.52, blue: 0.50, alpha: 1)
        case .venus: NSColor(red: 0.86, green: 0.74, blue: 0.52, alpha: 1)
        case .mars: NSColor(red: 0.74, green: 0.38, blue: 0.24, alpha: 1)
        case .jupiter: NSColor(red: 0.80, green: 0.68, blue: 0.54, alpha: 1)
        case .saturn: NSColor(red: 0.86, green: 0.78, blue: 0.60, alpha: 1)
        case .uranus: NSColor(red: 0.60, green: 0.84, blue: 0.88, alpha: 1)
        case .neptune: NSColor(red: 0.28, green: 0.44, blue: 0.86, alpha: 1)
        case .sun: NSColor(red: 1.00, green: 0.70, blue: 0.28, alpha: 1)
        }
    }

    /// Axial tilt in degrees, so each body leans the way it does in the sky.
    var tilt: Double {
        switch self {
        case .earth: 23.4
        case .moon: 6.7
        case .mercury: 0
        case .venus: 3
        case .mars: 25
        case .jupiter: 3
        case .saturn: 26.7
        case .uranus: 82
        case .neptune: 28
        case .sun: 7
        }
    }

    /// Seconds per turn at speed 1. Gas giants spin a little faster, as they do.
    var spinPeriod: Double {
        switch self {
        case .jupiter, .saturn: 40
        case .uranus, .neptune: 50
        case .sun: 80
        default: 60
        }
    }

    var hasRings: Bool { self == .saturn }
}
