import Foundation

/// The sound cfmac plays when a job (cleaning, maintenance, uninstalling, updating) finishes.
public enum CompletionSound: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, chime, tada, honey, burp, fart, swoosh, flush, pop, random

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "Silent"
        case .chime: "Chime"
        case .tada: "Ta-da!"
        case .honey: "Honey, it's done"
        case .burp: "Burp"
        case .fart: "Fart"
        case .swoosh: "Wind swoosh"
        case .flush: "Flush"
        case .pop: "Bubble pop"
        case .random: "Surprise me"
        }
    }

    public var emoji: String {
        switch self {
        case .none: "🔕"
        case .chime: "🔔"
        case .tada: "🎉"
        case .honey: "🍯"
        case .burp: "🥤"
        case .fart: "💨"
        case .swoosh: "🌬️"
        case .flush: "🚽"
        case .pop: "🫧"
        case .random: "🎲"
        }
    }

    /// What actually plays: synthesized audio, the spoken line, or nothing.
    public enum Playback: Equatable, Sendable {
        case silent
        case synthesized(SynthEffect)
        case spoken(VoiceLine)
    }

    /// Resolves `random` to a concrete sound using `pick`, which receives the candidates.
    public func playback(pick: ([CompletionSound]) -> CompletionSound? = { $0.randomElement() }) -> Playback {
        switch self {
        case .none: .silent
        case .chime: .synthesized(.chime)
        case .tada: .synthesized(.tada)
        case .honey: .spoken(.honeyItsDone)
        case .burp: .synthesized(.burp)
        case .fart: .synthesized(.fart)
        case .swoosh: .synthesized(.swoosh)
        case .flush: .synthesized(.flush)
        case .pop: .synthesized(.pop)
        case .random: (pick(Self.audible) ?? .chime).playback(pick: pick)
        }
    }

    /// Every sound that makes a noise and is not itself random.
    public static let audible: [CompletionSound] = allCases.filter { $0 != .none && $0 != .random }
}

/// A line spoken with the system voice, written in SSML for drawn-out, sing-song delivery.
public enum VoiceLine: Sendable, Equatable {
    case honeyItsDone

    public var text: String {
        switch self {
        case .honeyItsDone: "Honeyyy, it's doneee!"
        }
    }

    public var ssml: String {
        switch self {
        case .honeyItsDone:
            """
            <speak><prosody pitch="+30%" rate="55%">Honey,</prosody><break time="120ms"/>\
            <prosody pitch="+5%" rate="90%">it's</prosody> <prosody pitch="+25%" rate="40%">done!</prosody></speak>
            """
        }
    }
}
