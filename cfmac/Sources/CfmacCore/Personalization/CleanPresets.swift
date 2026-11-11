import Foundation

/// Named selections in Clean › Review.
public enum CleanPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case recommended, light, developer, everything, none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recommended: "Recommended"
        case .light: "Light weekly"
        case .developer: "Developer deep clean"
        case .everything: "Everything"
        case .none: "None"
        }
    }

    public var detail: String {
        switch self {
        case .recommended: "All Safe items"
        case .light: "Safe app, browser, chat and system caches. Skips developer tools, leftovers and the Trash"
        case .developer: "Safe items plus developer tools marked Review"
        case .everything: "Everything except size-only items"
        case .none: "Nothing selected"
        }
    }

    static let lightSections: Set<CleanSection> = [.system, .app, .browsers, .communication, .design, .ai, .cloud]

    public func selects(_ item: CleanItem) -> Bool {
        switch self {
        case .recommended: item.safety == .safe
        case .light: item.safety == .safe && Self.lightSections.contains(item.section)
        case .developer: item.safety == .safe || (item.section == .developer && item.safety == .review)
        case .everything: item.safety != .manual
        case .none: false
        }
    }

    public func selection(from items: [CleanItem]) -> Set<String> {
        Set(items.lazy.filter(selects).map(\.path))
    }
}

/// A folder the user added to Clean. Its contents are offered for review, never selected by default.
public struct CustomCleanFolder: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String

    public init(path: String) { self.path = path }

    public var name: String { (path as NSString).lastPathComponent }

    var candidate: CleanCandidate {
        CleanCandidate(path: path, label: name, detail: Paths.abbreviated(path), section: .custom, safety: .review, contentsOnly: true)
    }
}
