import AppKit
import SwiftUI

/// Rounded translucent panel used by Status cards and list groups.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.cardStroke))
    }
}

/// Small rounded tag ("M4", "Pressure high", "Wi-Fi").
struct Chip: View {
    let text: String
    var tint: Color = .ink

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint.opacity(0.88))
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.13)))
    }
}

/// Uppercase card heading with an icon.
struct SectionLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title.uppercased(), systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(Color.ink.opacity(0.72))
    }
}

/// Large number with a dimmed unit that animates when the value changes.
struct BigValue: View {
    let value: String
    let unit: String
    var size: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(Color.secondaryText)
        }
        .animation(Motion.value, value: value)
    }
}

struct MeterBar: View {
    let fraction: Double
    var tint: Color = .accentBlue
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ink.opacity(0.1))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .frame(height: height)
        .animation(Motion.value, value: fraction)
    }
}

/// History line for values in 0...1.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = .accentAmber
    var filled = true

    var body: some View {
        GeometryReader { geometry in
            let points = Self.points(values, in: geometry.size)
            ZStack {
                if filled, let first = points.first, let last = points.last {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                }
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: size.height - CGFloat(min(1, max(0, value))) * (size.height - 2) - 1)
        }
    }
}

/// The white capsule used for primary actions on hero screens.
struct HeroButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(prominent ? Color.inkInverse : Color.ink.opacity(0.85))
            .frame(minWidth: 236, minHeight: 46)
            .padding(.horizontal, 16)
            .background(Capsule().fill(prominent ? Color.ink : Color.ink.opacity(0.1)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = .ink
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.inkInverse : tint.opacity(0.9))
            .background(Capsule().fill(isSelected ? Color.ink : tint.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

/// Dimmed text with an inline link, as under hero headlines.
struct HeroSubtitle: View {
    let text: String
    var link: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(text).foregroundStyle(Color.secondaryText)
            if let link, let action {
                Button(link, action: action)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentBlue)
                    .fontWeight(.semibold)
            }
        }
        .font(.system(size: 12))
    }
}

struct AppIcon: View {
    let path: String
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// An SF Symbol that turns continuously.
struct SpinningSymbol: View {
    let name: String
    @Local private var angle: Double = 0

    var body: some View {
        Image(systemName: name)
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard !Motion.reduced else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { angle = 360 }
            }
    }
}

/// Fades and lifts content in when it first appears; `order` staggers siblings.
struct AppearEffect: ViewModifier {
    let order: Int
    @Local private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            .onAppear {
                if Motion.reduced {
                    visible = true
                } else {
                    withAnimation(.smooth(duration: 0.45).delay(Double(order) * 0.04)) { visible = true }
                }
            }
    }
}

extension View {
    func appearEffect(order: Int = 0) -> some View { modifier(AppearEffect(order: order)) }
}
