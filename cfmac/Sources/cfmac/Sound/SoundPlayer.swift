import AVFoundation
import AppKit
import SoundKit

/// Plays the chosen sound when a job finishes, and previews choices.
@MainActor
final class SoundPlayer: NSObject {
    static let shared = SoundPlayer()
    /// Rendered synthesized sounds kept in memory (each is 25–280 KB).
    private static let cacheLimit = 3

    private var rendered: [SynthEffect: Data] = [:]
    private var renderOrder: [SynthEffect] = []
    /// Held until playback ends; NSSound stops if released early.
    private var current: NSSound?
    private let speech = AVSpeechSynthesizer()

    /// Plays the sound for a finished job, unless quiet hours or the background-only option say not to.
    func playCompletion(for job: SoundJob) {
        let settings = AppSettings.shared
        if settings.soundQuietHours.contains(Date()) { return }
        if settings.soundsOnlyInBackground, NSApp.isActive { return }
        play(settings.sound(for: job))
    }

    func play(_ choice: SoundChoice) {
        stop()
        let volume = Float(AppSettings.shared.soundVolume)
        switch choice {
        case .builtIn(let sound):
            switch sound.playback() {
            case .silent: break
            case .synthesized(let effect): playSynthesized(effect, volume: volume)
            case .spoken(let line): speak(AVSpeechUtterance(ssmlRepresentation: line.ssml) ?? AVSpeechUtterance(string: line.text), voice: nil, volume: volume)
            }
        case .file(let fileName, _):
            guard let url = CustomSoundLibrary.url(for: fileName), let sound = NSSound(contentsOf: url, byReference: true) else { return }
            start(sound, volume: volume)
        case .spoken(let text, let voiceIdentifier):
            let utterance = AVSpeechUtterance(string: text)
            utterance.pitchMultiplier = 1.1
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
            speak(utterance, voice: voiceIdentifier, volume: volume)
        }
    }

    func stop() {
        current?.stop()
        current = nil
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
    }

    private func playSynthesized(_ effect: SynthEffect, volume: Float) {
        if let data = rendered[effect] {
            if let sound = NSSound(data: data) { start(sound, volume: volume) }
            return
        }
        // Rendering takes a few milliseconds; keep it off the main actor anyway.
        Task {
            let data = await Task.detached(priority: .userInitiated) { WAV.encode(SoundSynth.render(effect)) }.value
            remember(data, for: effect)
            if let sound = NSSound(data: data) { start(sound, volume: volume) }
        }
    }

    private func remember(_ data: Data, for effect: SynthEffect) {
        rendered[effect] = data
        renderOrder.removeAll { $0 == effect }
        renderOrder.append(effect)
        while renderOrder.count > Self.cacheLimit { rendered[renderOrder.removeFirst()] = nil }
    }

    private func start(_ sound: NSSound, volume: Float) {
        sound.volume = volume
        sound.delegate = self
        current = sound
        sound.play()
    }

    private func speak(_ utterance: AVSpeechUtterance, voice identifier: String?, volume: Float) {
        utterance.voice = identifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Self.preferredVoice
        utterance.volume = volume
        speech.speak(utterance)
    }

    /// A warm US English voice when installed, else the system default for English.
    static let preferredVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        for name in ["Samantha", "Ava", "Allison", "Susan", "Zoe"] {
            if let voice = english.filter({ $0.name.hasPrefix(name) }).max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
                return voice
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }()

    /// Installed voices for the user's languages, best quality first. All voices are on-device.
    static var voices: [AVSpeechSynthesisVoice] {
        let languages = Set(Locale.preferredLanguages.map { String($0.prefix(2)) } + ["en"])
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { languages.contains(String($0.language.prefix(2))) }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }
}

extension SoundPlayer: NSSoundDelegate {
    nonisolated func sound(_ sound: NSSound, didFinishPlaying finished: Bool) {
        MainActor.assumeIsolated {
            if current === sound { current = nil }
        }
    }
}

/// Sound files the user imported, copied into cfmac's private folder in Application Support.
@MainActor
enum CustomSoundLibrary {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cfmac/Sounds", isDirectory: true)
    }

    static func url(for fileName: String) -> URL? {
        // Only plain file names inside our folder are accepted.
        guard !fileName.contains("/"), !fileName.hasPrefix(".") else { return nil }
        let url = folder.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Validates and copies a user-chosen file. Returns the new choice, or why it was refused.
    static func importSound(from source: URL) -> Result<SoundChoice, ImportedSoundPolicy.Rejection> {
        let bytes = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        let seconds = NSSound(contentsOf: source, byReference: true)?.duration
        let existing = AppSettings.shared.savedSounds.filter { if case .file = $0 { return true } else { return false } }.count
        if let rejection = ImportedSoundPolicy.validate(fileExtension: source.pathExtension, bytes: bytes, seconds: seconds, existingCount: existing) {
            return .failure(rejection)
        }
        let fileName = UUID().uuidString + "." + source.pathExtension.lowercased()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let destination = folder.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            return .failure(.unreadable)
        }
        return .success(.file(fileName: fileName, title: source.deletingPathExtension().lastPathComponent))
    }

    static func delete(_ choice: SoundChoice) {
        if case .file(let fileName, _) = choice, let url = url(for: fileName) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
