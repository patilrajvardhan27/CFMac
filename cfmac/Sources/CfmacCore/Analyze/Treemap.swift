import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing and van Wijk). Rectangles keep input order.
public enum Treemap {
    public static func layout(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        let total = values.reduce(0) { $0 + max(0, $1) }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return values.map { _ in .zero } }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = values.map { max(0, $0) * scale }
        var rects = [CGRect](repeating: .zero, count: values.count)
        var remaining = bounds
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var best = worstRatio(areas[start..<end], side: side)
            while end < areas.count {
                let ratio = worstRatio(areas[start...end], side: side)
                if ratio > best { break }
                best = ratio
                end += 1
            }
            remaining = place(areas, start..<end, in: remaining, into: &rects)
            start = end
        }
        return rects
    }

    /// Lays one row along the shorter side and returns the space left over.
    private static func place(_ areas: [Double], _ row: Range<Int>, in rect: CGRect, into rects: inout [CGRect]) -> CGRect {
        let rowArea = areas[row].reduce(0, +)
        guard rowArea > 0 else { return rect }
        if rect.width >= rect.height {
            let width = CGFloat(rowArea / Double(rect.height))
            var y = rect.minY
            for index in row {
                let height = CGFloat(areas[index]) / width
                rects[index] = CGRect(x: rect.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
        } else {
            let height = CGFloat(rowArea / Double(rect.width))
            var x = rect.minX
            for index in row {
                let width = CGFloat(areas[index]) / height
                rects[index] = CGRect(x: x, y: rect.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
        }
    }

    private static func worstRatio(_ row: ArraySlice<Double>, side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard let largest = row.max(), let smallest = row.min(), sum > 0, smallest > 0, side > 0 else { return .infinity }
        return max(side * side * largest / (sum * sum), (sum * sum) / (side * side * smallest))
    }
}
