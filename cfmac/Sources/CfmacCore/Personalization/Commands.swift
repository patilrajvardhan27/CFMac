import Foundation

/// Fuzzy matching for the command palette: every query character must appear in order.
/// Consecutive characters and word starts score higher. O(query + candidate).
public enum FuzzyMatch {
    public static func score(_ query: String, in candidate: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(candidate.lowercased())
        var score = 0
        var index = 0
        var previousMatch = -2
        for (position, character) in haystack.enumerated() where index < needle.count && character == needle[index] {
            let atWordStart = position == 0 || !haystack[position - 1].isLetter
            score += 1 + (position == previousMatch + 1 ? 5 : 0) + (atWordStart ? 8 : 0)
            previousMatch = position
            index += 1
        }
        guard index == needle.count else { return nil }
        // Prefer shorter candidates when scores tie.
        return score * 100 - haystack.count
    }

    /// `items` ranked by best score across their searchable strings; non-matches dropped.
    public static func rank<T>(_ items: [T], query: String, strings: (T) -> [String]) -> [T] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return
            items
            .compactMap { item in strings(item).compactMap { score(query, in: $0) }.max().map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}

/// A global keyboard shortcut, stored with Carbon modifier flags.
public struct KeyCombo: Codable, Hashable, Sendable {
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    public let keyCode: UInt32
    public let modifiers: UInt32
    /// The key's printed name at recording time ("K", "F5", "Space").
    public let key: String

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public var modifierCount: Int {
        [Self.control, Self.option, Self.shift, Self.command].filter { modifiers & $0 != 0 }.count
    }

    /// Global shortcuts need two or more modifiers so they don't steal ordinary typing.
    public var isValidGlobal: Bool { modifierCount >= 2 && !key.isEmpty }

    public var display: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + key.uppercased()
    }
}
