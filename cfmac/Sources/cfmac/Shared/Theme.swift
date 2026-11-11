import AppKit
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case clean, apps, optimize, analyze, status
    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: "Clean"
        case .apps: "Apps"
        case .optimize: "Optimize"
        case .analyze: "Analyze"
        case .status: "Status"
        }
    }

    /// The window title for each tab.
    var windowTitle: String { self == .apps ? "Software" : title }

    /// Each tab tints the window with its own color (0xRRGGBB), which users can change.
    var defaultTint: UInt32 {
        switch self {
        case .clean: 0x272B40
        case .apps: 0x33201F
        case .optimize: 0x353130
        case .analyze: 0x43301F
        case .status: 0x3D3420
        }
    }

    /// Dark mode: the tint fading darker. Light mode: a soft wash of the same hue.
    func gradient(tint: UInt32?) -> [Color] {
        let base = NSColor(hex: tint ?? defaultTint)
        let top = NSColor(name: nil) { appearance in
            appearance.isDark ? base : base.blended(withFraction: 0.84, of: .white) ?? .white
        }
        let bottom = NSColor(name: nil) { appearance in
            appearance.isDark ? base.shadow(withLevel: 0.32) ?? base : base.blended(withFraction: 0.92, of: .white) ?? .white
        }
        return [Color(nsColor: top), Color(nsColor: bottom)]
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    var hexValue: UInt32 {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
        return channel(rgb.redComponent) << 16 | channel(rgb.greenComponent) << 8 | channel(rgb.blueComponent)
    }

    /// A color that switches between `dark` and `light` with the current appearance.
    static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.isDark ? dark : light }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: opacity))
    }

    /// Main foreground on cfmac's tinted backgrounds: white in dark mode, near-black in light.
    static let ink = Color(nsColor: .adaptive(dark: .white, light: NSColor(white: 0.1, alpha: 1)))
    /// Text on an `ink`-filled control.
    static let inkInverse = Color(nsColor: .adaptive(dark: .black, light: .white))
    static let secondaryText = Color.ink.opacity(0.58)
    static let cardFill = Color.ink.opacity(0.06)
    static let cardStroke = Color.ink.opacity(0.09)

    static let accentGreen = Color(nsColor: .adaptive(dark: NSColor(hex: 0x5FB98A), light: NSColor(hex: 0x2E8A5C)))
    static let accentRed = Color(nsColor: .adaptive(dark: NSColor(hex: 0xD46A6A), light: NSColor(hex: 0xB83A3A)))
    static let accentAmber = Color(nsColor: .adaptive(dark: NSColor(hex: 0xE0B060), light: NSColor(hex: 0xA86F10)))
    /// Links and highlights; follows the macOS accent color when the user asks for it.
    static let accentBlue = Color(
        nsColor: NSColor(name: nil) { appearance in
            if UserDefaults.standard.useSystemAccentColor { return .controlAccentColor }
            return appearance.isDark ? NSColor(hex: 0x7EA2E8) : NSColor(hex: 0x2F5BC0)
        })
}

extension UserDefaults {
    /// Read at draw time by `Color.accentBlue`; written by `AppSettings`.
    var useSystemAccentColor: Bool {
        guard let data = data(forKey: "useSystemAccent") else { return false }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }
}

/// Shared animations. All of them turn off under Reduce Motion.
@MainActor
enum Motion {
    static var tab: Animation? { reduced ? nil : .smooth(duration: 0.35) }
    static var content: Animation? { reduced ? nil : .smooth(duration: 0.3) }
    static var value: Animation? { reduced ? nil : .snappy(duration: 0.45) }

    static var reduced: Bool { AppSettings.shared.motionReduced }
}
