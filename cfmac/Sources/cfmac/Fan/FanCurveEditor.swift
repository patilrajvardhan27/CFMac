import FanService
import SwiftUI

/// Drag the points to shape Cool mode: temperature across, fan speed up.
struct FanCurveEditor: View {
    @Binding var curve: FanCurve
    /// Current chip temperature, drawn as a marker.
    var temperature: Double?

    private let range = FanCurve.temperatureRange
    private static let pointSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                grid(size)
                curvePath(size).stroke(Color.accentBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let temperature, range.contains(temperature) {
                    let x = xPosition(temperature, size)
                    Path {
                        $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    .stroke(Color.accentAmber.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    Text("\(Int(temperature))°C now").font(.caption2).foregroundStyle(Color.accentAmber).offset(x: x + 4, y: 2)
                }
                ForEach(Array(curve.points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(Color.accentBlue)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                        .frame(width: Self.pointSize, height: Self.pointSize)
                        .position(x: xPosition(point.temperature, size), y: yPosition(point.fraction, size))
                        .gesture(
                            DragGesture(minimumDistance: 0).onChanged { drag in
                                curve = curve.moving(
                                    index,
                                    to: FanCurve.Point(
                                        temperature: temperature(at: drag.location.x, size).rounded(),
                                        fraction: fraction(at: drag.location.y, size)
                                    ))
                            }
                        )
                        .help("\(Int(point.temperature))°C → \(Int((point.fraction * 100).rounded()))% speed")
                }
            }
        }
        .frame(height: 180)
        .padding(.leading, 34)
        .padding(.bottom, 18)
        .overlay(alignment: .bottomLeading) { axisLabels }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fan curve")
        .accessibilityValue(curve.points.map { "\(Int($0.temperature)) degrees, \(Int($0.fraction * 100)) percent" }.joined(separator: "; "))
    }

    private func grid(_ size: CGSize) -> some View {
        Path { path in
            for step in stride(from: range.lowerBound, through: range.upperBound, by: 10) {
                let x = xPosition(step, size)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for step in stride(from: 0.0, through: 1, by: 0.25) {
                let y = yPosition(step, size)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
    }

    private func curvePath(_ size: CGSize) -> Path {
        Path { path in
            guard let first = curve.points.first, let last = curve.points.last else { return }
            path.move(to: CGPoint(x: 0, y: yPosition(first.fraction, size)))
            for point in curve.points { path.addLine(to: CGPoint(x: xPosition(point.temperature, size), y: yPosition(point.fraction, size))) }
            path.addLine(to: CGPoint(x: size.width, y: yPosition(last.fraction, size)))
        }
    }

    private var axisLabels: some View {
        HStack {
            Text("\(Int(range.lowerBound))°C")
            Spacer()
            Text("Chip temperature")
            Spacer()
            Text("\(Int(range.upperBound))°C")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.leading, 34)
    }

    private func xPosition(_ temperature: Double, _ size: CGSize) -> CGFloat {
        CGFloat((temperature - range.lowerBound) / (range.upperBound - range.lowerBound)) * size.width
    }

    private func yPosition(_ fraction: Double, _ size: CGSize) -> CGFloat {
        size.height - CGFloat(fraction) * size.height
    }

    private func temperature(at x: CGFloat, _ size: CGSize) -> Double {
        range.lowerBound + Double(min(max(0, x), size.width) / max(1, size.width)) * (range.upperBound - range.lowerBound)
    }

    private func fraction(at y: CGFloat, _ size: CGSize) -> Double {
        1 - Double(min(max(0, y), size.height) / max(1, size.height))
    }
}
