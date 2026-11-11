import Foundation

/// Display formatting. Values are formatted for people; never parse these strings back.
public enum Format {
    public static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: max(0, value))
    }

    /// Splits "165.2 GB" into ("165.2", "GB") for large-number layouts.
    public static func bytesParts(_ value: Int64) -> (number: String, unit: String) {
        split(bytes(value))
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 1024 else { return "<1 KB/s" }
        return bytes(Int64(bytesPerSecond)) + "/s"
    }

    public static func rateParts(_ bytesPerSecond: Double) -> (number: String, unit: String) {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 1024 else { return ("0", "KB/s") }
        let parts = split(bytes(Int64(bytesPerSecond)))
        return (parts.number, parts.unit + "/s")
    }

    public static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter.string(from: max(0, seconds)) ?? "–"
    }

    public static func percent(_ fraction: Double) -> Int {
        Int((min(1, max(0, fraction)) * 100).rounded())
    }

    private static func split(_ text: String) -> (number: String, unit: String) {
        guard let space = text.lastIndex(where: \.isWhitespace) else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }
}
