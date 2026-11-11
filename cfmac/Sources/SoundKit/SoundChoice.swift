import Foundation

/// Jobs that can each have their own sound.
public enum SoundJob: String, CaseIterable, Codable, Identifiable, Sendable {
    case clean, optimize, uninstall, update
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .clean: "Cleaning finished"
        case .optimize: "Maintenance finished"
        case .uninstall: "Uninstall finished"
        case .update: "Updates finished"
        }
    }
}

/// What to play: a built-in sound, a sound file the user imported, or a line the user typed.
public enum SoundChoice: Codable, Hashable, Sendable {
    case builtIn(CompletionSound)
    /// `fileName` names a copy kept in cfmac's own Application Support folder.
    case file(fileName: String, title: String)
    case spoken(text: String, voiceIdentifier: String?)

    public static let maximumSpokenLength = 80

    public var title: String {
        switch self {
        case .builtIn(let sound): sound.title
        case .file(_, let title): title
        case .spoken(let text, _): "“\(text)”"
        }
    }

    public var emoji: String {
        switch self {
        case .builtIn(let sound): sound.emoji
        case .file: "🎵"
        case .spoken: "🗣️"
        }
    }

    public var isSilent: Bool { self == .builtIn(.none) }

    /// Trims and limits a typed line so it stays a short "done" phrase.
    public static func cleanedSpokenText(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maximumSpokenLength))
    }
}

/// Rules for sound files the user imports. Files are copied into cfmac's folder, so the
/// original can move or be deleted; nothing is ever uploaded.
public enum ImportedSoundPolicy {
    public static let allowedExtensions: Set<String> = ["aiff", "aif", "caf", "m4a", "mp3", "wav"]
    public static let maximumBytes = 5 * 1_048_576
    public static let maximumSeconds: Double = 15
    public static let maximumCount = 20

    public enum Rejection: Error, Equatable, Sendable {
        case unsupportedType, tooLarge, tooLong, tooMany, unreadable

        public var message: String {
            switch self {
            case .unsupportedType: "Choose an AIFF, CAF, M4A, MP3 or WAV file."
            case .tooLarge: "Choose a file under 5 MB."
            case .tooLong: "Choose a sound under 15 seconds."
            case .tooMany: "You can keep up to 20 sounds. Remove one first."
            case .unreadable: "That file could not be played."
            }
        }
    }

    public static func validate(fileExtension: String, bytes: Int, seconds: Double?, existingCount: Int) -> Rejection? {
        guard allowedExtensions.contains(fileExtension.lowercased()) else { return .unsupportedType }
        guard bytes <= maximumBytes else { return .tooLarge }
        guard existingCount < maximumCount else { return .tooMany }
        guard let seconds, seconds > 0 else { return .unreadable }
        guard seconds <= maximumSeconds else { return .tooLong }
        return nil
    }
}
