import AppKit

/// Menu bar runners. Frames come from the artwork folder (`runners/<name>/frame-N.png`).
public enum Runner: String, CaseIterable, Identifiable, Codable, Sendable {
    case cat, beagle, fox, frog, rabbit, dinosaur
    case rubberDuck = "rubber-duck"
    case bird, chicken, deer, dolphin, horse, otter, squirrel, turtle
    case shibaInu = "shiba-inu"
    case welshCorgi = "welsh-corgi"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rubberDuck: "Rubber Duck"
        case .shibaInu: "Shiba Inu"
        case .welshCorgi: "Welsh Corgi"
        default: rawValue.capitalized
        }
    }

    /// Template images in playback order, sized for the menu bar. Empty when not installed.
    public func frames(height: CGFloat = 18) -> [NSImage] {
        guard let folder = ArtworkLibrary.url("runners/\(rawValue)"),
            let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return [] }
        let indexed: [(Int, String)] = names.compactMap { name in
            guard name.hasPrefix("frame-"), name.hasSuffix(".png"),
                let index = Int(name.dropFirst("frame-".count).dropLast(".png".count))
            else { return nil }
            return (index, name)
        }
        return indexed.sorted { $0.0 < $1.0 }.compactMap { _, name in
            guard let image = NSImage(contentsOf: folder.appendingPathComponent(name)), image.size.height > 0 else { return nil }
            image.size = NSSize(width: (image.size.width * height / image.size.height).rounded(), height: height)
            image.isTemplate = true
            return image
        }
    }
}

public enum RunnerFrames {
    /// Seconds per frame when idle and when fully busy.
    static let idleInterval: TimeInterval = 0.25
    static let busyInterval: TimeInterval = 0.04

    /// Frame duration for `load` (0...1, clamped): the busier, the faster the runner.
    public static func frameInterval(load: Double) -> TimeInterval {
        let clamped = load.isFinite ? min(1, max(0, load)) : 0
        return idleInterval - (idleInterval - busyInterval) * clamped
    }
}
